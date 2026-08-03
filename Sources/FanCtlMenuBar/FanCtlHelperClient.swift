import FanCtlHelperXPC
import CryptoKit
import Dispatch
import Foundation
import Security
import ServiceManagement

enum FanCtlHelperClient {
    // A complete transaction can wait up to roughly ten seconds per fan for
    // firmware to release manual mode. Keep this above the ten-fan core limit.
    static let fanCommandTimeout: TimeInterval = 120.0
    // Automatic recovery retries mode changes for every enumerated fan and
    // verifies Ftst afterward. Do not time out while the helper still owns the
    // serialized mutation and is actively restoring the safe state.
    static let automaticFallbackTimeout: TimeInterval = 20.0
    private static let sequenceGenerator = MutationSequenceGenerator()
    private static let connectionPool = XPCConnectionPool()

    enum Error: LocalizedError {
        case unavailable
        case rejected(code: String?, message: String)
        case invalidResponse
        case incompatibleHelper

        var errorDescription: String? {
            switch self {
            case .unavailable:
                L10n.helperUnavailable
            case .rejected(_, let message):
                message
            case .invalidResponse:
                L10n.invalidHelperResponse
            case .incompatibleHelper:
                L10n.incompatibleHelper
            }
        }

    }

    static func waitUntilAvailable(timeout: TimeInterval) async throws {
        guard timeout.isFinite, timeout > 0 else {
            throw Error.unavailable
        }
        let start = DispatchTime.now().uptimeNanoseconds
        var lastError: Swift.Error = Error.unavailable
        var retryDelay: TimeInterval = 0.1

        while true {
            try Task.checkCancellation()
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
            let remaining = timeout - elapsed
            guard remaining > 0 else {
                throw lastError
            }

            do {
                _ = try await send("GET_VERSION", timeout: min(0.75, remaining))
                return
            } catch let error as Error {
                switch error {
                case .unavailable:
                    lastError = error
                case .rejected, .invalidResponse, .incompatibleHelper:
                    // A protocol, authorization, or compatibility failure cannot
                    // be repaired by reconnecting to the same helper.
                    throw error
                }
            } catch {
                lastError = error
            }

            let currentElapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
            let sleepInterval = min(retryDelay, max(0, timeout - currentElapsed))
            guard sleepInterval > 0 else {
                throw lastError
            }
            try await Task.sleep(nanoseconds: UInt64(sleepInterval * 1_000_000_000))
            retryDelay = min(retryDelay * 2, 1.0)
        }
    }

    static func invalidateConnection() {
        connectionPool.invalidate()
    }

    static func nextMutationSequence() -> Int64 {
        sequenceGenerator.next()
    }

    static func send(
        _ command: String,
        timeout: TimeInterval = 5.0,
        mutationSequence: Int64? = nil
    ) async throws -> String {
        guard timeout.isFinite, timeout > 0 else {
            throw Error.unavailable
        }
        let timeoutNanoseconds = UInt64(min(timeout, 3_600) * 1_000_000_000)
        let resolvedSequence = isMutationCommand(command)
            ? (mutationSequence ?? nextMutationSequence())
            : nil

        return try await withThrowingTaskGroup(of: String.self) { group in
            defer { group.cancelAll() }
            group.addTask {
                try await sendWithoutTimeout(command, mutationSequence: resolvedSequence)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw Error.unavailable
            }

            guard let result = try await group.next() else {
                throw Error.unavailable
            }
            return result
        }
    }

    private static func sendWithoutTimeout(
        _ command: String,
        mutationSequence: Int64?
    ) async throws -> String {
        let connection = connectionPool.connection()
        let requestHandle = XPCRequestHandle()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let requestID = UUID()
                let state = XPCReplyState(
                    continuation: continuation,
                    onFinish: {
                        connectionPool.removeRequest(requestID)
                    }
                )
                guard connectionPool.register(
                    state,
                    id: requestID,
                    for: connection
                ) else {
                    state.finish(.failure(Error.unavailable))
                    return
                }
                requestHandle.attach(state)
                let reply: (NSString?, NSString?) -> Void = { response, errorMessage in
                    if let response {
                        state.finish(.success(response as String))
                    } else if let errorMessage {
                        let encoded = errorMessage as String
                        if let failure = FanCtlHelperWire.decodeFailure(encoded) {
                            state.finish(.failure(Error.rejected(code: failure.code, message: failure.message)))
                        } else {
                            state.finish(.failure(Error.rejected(code: nil, message: encoded)))
                        }
                    } else {
                        state.finish(.failure(Error.invalidResponse))
                    }
                }

                if Task.isCancelled {
                    state.finish(.failure(CancellationError()))
                    return
                }

                guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                    state.finish(.failure(Error.unavailable))
                }) as? FanCtlHelperXPCProtocol else {
                    state.finish(.failure(Error.unavailable))
                    return
                }

                do {
                    let sequenceNumber = mutationSequence.map { NSNumber(value: $0) }
                    switch command {
                    case "PING":
                        proxy.ping(withReply: reply)
                    case "GET_VERSION":
                        proxy.getVersion { version, helperBuild in
                            guard version.intValue == FanCtlHelperConstants.protocolVersion else {
                                state.finish(.failure(Error.incompatibleHelper))
                                return
                            }
                            if let expectedBuild = currentApplicationBuild,
                               helperBuild.length > 0,
                               helperBuild as String != "unknown",
                               helperBuild as String != expectedBuild {
                                state.finish(.failure(Error.incompatibleHelper))
                                return
                            }
                            state.finish(.success("version \(version.intValue) build \(helperBuild)"))
                        }
                    case "SET_AUTOMATIC":
                        guard let sequenceNumber else {
                            throw Error.invalidResponse
                        }
                        proxy.setAutomatic(sequenceNumber, withReply: reply)
                    case "SET_MAXIMUM":
                        guard let sequenceNumber else {
                            throw Error.invalidResponse
                        }
                        proxy.setMaximum(sequenceNumber, withReply: reply)
                    case "RENEW_MANUAL_LEASE":
                        guard let sequenceNumber else {
                            throw Error.invalidResponse
                        }
                        proxy.renewManualControlLease(sequenceNumber, withReply: reply)
                    case "REMOVE_LEGACY_MANUAL_HELPER":
                        guard let sequenceNumber else {
                            throw Error.invalidResponse
                        }
                        proxy.removeLegacyManualHelperInstall(
                            sequenceNumber,
                            withReply: reply
                        )
                    default:
                        if command.hasPrefix("SET_RPM ") {
                            let rawRPM = String(command.dropFirst("SET_RPM ".count))
                            guard let rpm = Int(rawRPM),
                                  (FanCtlHelperConstants.minimumRPM...FanCtlHelperConstants.maximumEncodedRPM).contains(rpm) else {
                                throw Error.rejected(code: "invalid_request", message: L10n.invalidHelperResponse)
                            }
                            guard let sequenceNumber else {
                                throw Error.invalidResponse
                            }
                            proxy.setRPM(NSNumber(value: rpm), sequence: sequenceNumber, withReply: reply)
                        } else {
                            throw Error.rejected(code: "invalid_request", message: L10n.invalidHelperResponse)
                        }
                    }
                } catch {
                    state.finish(.failure(error))
                }
            }
        } onCancel: {
            requestHandle.cancel()
        }
    }

    private static var currentApplicationBuild: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func isMutationCommand(_ command: String) -> Bool {
        command == "SET_AUTOMATIC" ||
            command == "SET_MAXIMUM" ||
            command == "RENEW_MANUAL_LEASE" ||
            command == "REMOVE_LEGACY_MANUAL_HELPER" ||
            command.hasPrefix("SET_RPM ")
    }
}

private final class MutationSequenceGenerator: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int64

    init() {
        let uptime = DispatchTime.now().uptimeNanoseconds
        value = Int64(min(uptime, UInt64(Int64.max - 1_000_000)))
    }

    func next() -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        if value == Int64.max {
            value = 0
        } else {
            value += 1
        }
        return value
    }
}

private final class XPCConnectionPool: @unchecked Sendable {
    private let lock = NSLock()
    private var activeConnection: NSXPCConnection?
    private var activeRequests: [UUID: XPCReplyState] = [:]

    func connection() -> NSXPCConnection {
        lock.lock()
        defer { lock.unlock() }

        if let activeConnection {
            return activeConnection
        }

        let connection = NSXPCConnection(
            machServiceName: FanCtlHelperConstants.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: FanCtlHelperXPCProtocol.self)
        connection.interruptionHandler = { [weak self, weak connection] in
            guard let connection else {
                return
            }
            self?.failRequestsForInterruptedConnection(connection)
        }
        connection.invalidationHandler = { [weak self, weak connection] in
            guard let connection else {
                return
            }
            self?.discardInvalidatedConnection(connection)
        }
        connection.resume()
        activeConnection = connection
        return connection
    }

    func invalidate() {
        lock.lock()
        let connection = activeConnection
        activeConnection = nil
        let requests = Array(activeRequests.values)
        activeRequests.removeAll()
        lock.unlock()

        for request in requests {
            request.finish(.failure(FanCtlHelperClient.Error.unavailable))
        }
        guard let connection else {
            return
        }

        connection.interruptionHandler = nil
        connection.invalidationHandler = nil
        connection.invalidate()
    }

    func register(
        _ request: XPCReplyState,
        id: UUID,
        for connection: NSXPCConnection
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard activeConnection === connection else {
            return false
        }
        activeRequests[id] = request
        return true
    }

    func removeRequest(_ id: UUID) {
        lock.withLock {
            _ = activeRequests.removeValue(forKey: id)
        }
    }

    private func failRequestsForInterruptedConnection(_ connection: NSXPCConnection) {
        lock.lock()
        guard activeConnection === connection else {
            lock.unlock()
            return
        }
        let requests = Array(activeRequests.values)
        activeRequests.removeAll()
        lock.unlock()

        for request in requests {
            request.finish(.failure(FanCtlHelperClient.Error.unavailable))
        }
    }

    private func discardInvalidatedConnection(_ connection: NSXPCConnection) {
        lock.lock()
        guard activeConnection === connection else {
            lock.unlock()
            return
        }
        activeConnection = nil
        let requests = Array(activeRequests.values)
        activeRequests.removeAll()
        lock.unlock()

        for request in requests {
            request.finish(.failure(FanCtlHelperClient.Error.unavailable))
        }
    }
}

private final class XPCRequestHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var state: XPCReplyState?
    private var isCancelled = false

    func attach(_ state: XPCReplyState) {
        lock.lock()
        if isCancelled {
            lock.unlock()
            state.finish(.failure(CancellationError()))
            return
        }
        self.state = state
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let state = state
        lock.unlock()
        state?.finish(.failure(CancellationError()))
    }
}

private final class XPCReplyState: @unchecked Sendable {
    private let lock = NSLock()
    private let continuation: CheckedContinuation<String, Swift.Error>
    private let onFinish: @Sendable () -> Void
    private var didFinish = false

    init(
        continuation: CheckedContinuation<String, Swift.Error>,
        onFinish: @escaping @Sendable () -> Void
    ) {
        self.continuation = continuation
        self.onFinish = onFinish
    }

    func finish(_ result: Result<String, Swift.Error>) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        lock.unlock()

        onFinish()
        switch result {
        case .success(let response):
            continuation.resume(returning: response)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

enum FanCtlHelperInstaller {
    private static let registeredHelperFingerprintKey = "registeredFanControlHelperFingerprint"
    private static let pendingHelperFingerprintKey = "pendingFanControlHelperFingerprint"
    private static let legacyRegisteredHelperBuildKey = "registeredFanControlHelperBuild"
    private static let legacyPendingHelperBuildKey = "pendingFanControlHelperBuild"

    static var serviceStatus: FanCtlHelperServiceStatus {
        let service = SMAppService.daemon(plistName: FanCtlHelperConstants.daemonPlistName)
        switch service.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered, .notFound:
            return .inactive
        @unknown default:
            return .inactive
        }
    }

    static func install() async throws {
        try validateContainingApplication()
        try await reconcileRegistration(forceReinstall: false)
    }

    static func reinstall() async throws {
        try validateContainingApplication()
        try await reconcileRegistration(forceReinstall: true)
    }

    private static func validateContainingApplication() throws {
        guard isTrustedContainingApplication else {
            throw InstallError.untrustedApplication
        }
        guard isInstalledApplication else {
            throw InstallError.unstableApplicationLocation
        }
        guard currentFingerprint != nil else {
            throw InstallError.invalidBundledHelper
        }
    }

    private static func reconcileRegistration(forceReinstall: Bool) async throws {
        guard let currentFingerprint else {
            throw InstallError.invalidBundledHelper
        }
        let service = SMAppService.daemon(plistName: FanCtlHelperConstants.daemonPlistName)
        let registeredFingerprint = UserDefaults.standard.string(
            forKey: registeredHelperFingerprintKey
        )
        let pendingFingerprint = UserDefaults.standard.string(
            forKey: pendingHelperFingerprintKey
        )

        let action = FanCtlHelperRegistrationPlanner.action(
            status: registrationStatus(for: service),
            forceReinstall: forceReinstall,
            currentFingerprint: currentFingerprint,
            registeredFingerprint: registeredFingerprint,
            pendingFingerprint: pendingFingerprint
        )

        switch action {
        case .none:
            clearPendingFingerprint()
        case .adoptPendingRegistration:
            // A previous refresh reached the approval step. An enabled service now
            // means macOS completed that registration.
            rememberRegisteredFingerprint(currentFingerprint)
            clearPendingFingerprint()
        case .register:
            clearStoredRegistration()
            try register(service)
        case .replace:
            try await unregister(service)
            clearStoredRegistration()
            try register(service)
        case .awaitApproval:
            throw InstallError.requiresApproval
        }
    }

    private static func registrationStatus(
        for service: SMAppService
    ) -> FanCtlHelperRegistrationStatus {
        switch service.status {
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notRegistered, .notFound:
            .inactive
        @unknown default:
            .inactive
        }
    }

    private static func unregister(_ service: SMAppService) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Swift.Error>) in
            service.unregister { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private static func register(_ service: SMAppService) throws {
        guard let currentFingerprint else {
            throw InstallError.invalidBundledHelper
        }
        do {
            try service.register()
        } catch {
            if service.status == .requiresApproval {
                rememberPendingFingerprint(currentFingerprint)
                throw InstallError.requiresApproval
            }
            throw error
        }

        switch service.status {
        case .enabled:
            rememberRegisteredFingerprint(currentFingerprint)
            clearPendingFingerprint()
        case .requiresApproval:
            rememberPendingFingerprint(currentFingerprint)
            throw InstallError.requiresApproval
        case .notRegistered, .notFound:
            throw InstallError.registrationDidNotStart
        @unknown default:
            rememberRegisteredFingerprint(currentFingerprint)
        }
    }

    private static let currentFingerprint: String? = {
        guard let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              !build.isEmpty else {
            return nil
        }
        let helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchServices", isDirectory: true)
            .appendingPathComponent(FanCtlHelperConstants.helperExecutableName)
        let daemonPlistURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchDaemons", isDirectory: true)
            .appendingPathComponent(FanCtlHelperConstants.daemonPlistName)
        guard let helperData = try? Data(contentsOf: helperURL, options: .mappedIfSafe),
              let daemonPlistData = try? Data(
                  contentsOf: daemonPlistURL,
                  options: .mappedIfSafe
              ) else {
            return nil
        }
        let helperDigest = SHA256.hash(data: helperData)
            .map { String(format: "%02x", $0) }
            .joined()
        let daemonPlistDigest = SHA256.hash(data: daemonPlistData)
            .map { String(format: "%02x", $0) }
            .joined()
        let bundlePath = Bundle.main.bundleURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        return [
            build,
            String(FanCtlHelperConstants.protocolVersion),
            FanCtlHelperConstants.helperExecutableName,
            helperDigest,
            daemonPlistDigest,
            bundlePath
        ].joined(separator: ":")
    }()

    private static var isTrustedContainingApplication: Bool {
        guard Bundle.main.bundleIdentifier ==
                FanCtlHelperConstants.appBundleIdentifier,
              Bundle.main.object(
                  forInfoDictionaryKey: "FanControlDistributionBuild"
              ) as? Bool == true else {
            return false
        }

        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess,
              let code else {
            return false
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode,
              SecStaticCodeCheckValidity(
                  staticCode,
                  SecCSFlags(),
                  nil
              ) == errSecSuccess else {
            return false
        }

        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
              let dictionary = information as? [String: Any],
              let teamIdentifier = dictionary[kSecCodeInfoTeamIdentifier as String] as? String,
              teamIdentifier == FanCtlHelperConstants.developerTeamIdentifier else {
            return false
        }
        return true
    }

    private static var isInstalledApplication: Bool {
        FanCtlApplicationLocation.isInstalledApplication()
    }

    private static func rememberRegisteredFingerprint(_ fingerprint: String) {
        UserDefaults.standard.set(fingerprint, forKey: registeredHelperFingerprintKey)
        UserDefaults.standard.removeObject(forKey: legacyRegisteredHelperBuildKey)
    }

    private static func rememberPendingFingerprint(_ fingerprint: String) {
        UserDefaults.standard.set(fingerprint, forKey: pendingHelperFingerprintKey)
        UserDefaults.standard.removeObject(forKey: legacyPendingHelperBuildKey)
    }

    private static func clearPendingFingerprint() {
        UserDefaults.standard.removeObject(forKey: pendingHelperFingerprintKey)
        UserDefaults.standard.removeObject(forKey: legacyPendingHelperBuildKey)
    }

    private static func clearStoredRegistration() {
        UserDefaults.standard.removeObject(forKey: registeredHelperFingerprintKey)
        UserDefaults.standard.removeObject(forKey: pendingHelperFingerprintKey)
        UserDefaults.standard.removeObject(forKey: legacyRegisteredHelperBuildKey)
        UserDefaults.standard.removeObject(forKey: legacyPendingHelperBuildKey)
    }
}

enum FanCtlHelperServiceStatus {
    case enabled
    case requiresApproval
    case inactive
}

enum InstallError: LocalizedError {
    case requiresApproval
    case registrationDidNotStart
    case untrustedApplication
    case unstableApplicationLocation
    case invalidBundledHelper

    var errorDescription: String? {
        switch self {
        case .requiresApproval:
            L10n.helperRequiresApproval
        case .registrationDidNotStart:
            L10n.helperRegistrationFailed
        case .untrustedApplication:
            L10n.signedReleaseRequired
        case .unstableApplicationLocation:
            L10n.installInApplicationsRequired
        case .invalidBundledHelper:
            L10n.invalidBundledHelper
        }
    }
}
