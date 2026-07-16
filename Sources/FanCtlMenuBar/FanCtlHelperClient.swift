import FanCtlHelperXPC
import Dispatch
import Foundation
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
        let deadline = Date().addingTimeInterval(timeout)
        var lastError: Swift.Error = Error.unavailable

        while true {
            try Task.checkCancellation()
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else {
                throw lastError
            }

            do {
                _ = try await send("GET_VERSION", timeout: min(0.75, remaining))
                return
            } catch Error.incompatibleHelper {
                throw Error.incompatibleHelper
            } catch {
                lastError = error
                let sleepInterval = min(0.1, max(0, deadline.timeIntervalSinceNow))
                guard sleepInterval > 0 else {
                    throw lastError
                }
                try await Task.sleep(nanoseconds: UInt64(sleepInterval * 1_000_000_000))
            }
        }
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
        let connection = NSXPCConnection(
            machServiceName: FanCtlHelperConstants.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: FanCtlHelperXPCProtocol.self)

        let connectionHandle = XPCConnectionHandle(connection)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let state = XPCReplyState(connectionHandle: connectionHandle, continuation: continuation)
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

                connection.interruptionHandler = {
                    state.finish(.failure(Error.unavailable))
                }
                connection.invalidationHandler = {
                    state.finish(.failure(Error.unavailable))
                }

                if Task.isCancelled {
                    state.finish(.failure(CancellationError()))
                    return
                }

                connection.resume()
                guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                    NSLog("mFanCtl helper XPC transport error: \(error.localizedDescription)")
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
            connectionHandle.invalidate()
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

private final class XPCConnectionHandle: @unchecked Sendable {
    private let lock = NSLock()
    private let connection: NSXPCConnection
    private var didInvalidate = false

    init(_ connection: NSXPCConnection) {
        self.connection = connection
    }

    func invalidate() {
        lock.lock()
        guard !didInvalidate else {
            lock.unlock()
            return
        }
        didInvalidate = true
        lock.unlock()
        connection.interruptionHandler = nil
        connection.invalidationHandler = nil
        connection.invalidate()
    }
}

private final class XPCReplyState: @unchecked Sendable {
    private let lock = NSLock()
    private let connectionHandle: XPCConnectionHandle
    private let continuation: CheckedContinuation<String, Swift.Error>
    private var didFinish = false

    init(connectionHandle: XPCConnectionHandle, continuation: CheckedContinuation<String, Swift.Error>) {
        self.connectionHandle = connectionHandle
        self.continuation = continuation
    }

    func finish(_ result: Result<String, Swift.Error>) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        lock.unlock()

        switch result {
        case .success(let response):
            continuation.resume(returning: response)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
        connectionHandle.invalidate()
    }
}

enum FanCtlHelperInstaller {
    private static let registeredHelperBuildKey = "registeredFanControlHelperBuild"
    private static let pendingHelperBuildKey = "pendingFanControlHelperBuild"

    static func install() throws {
        let service = SMAppService.daemon(plistName: FanCtlHelperConstants.daemonPlistName)
        switch service.status {
        case .enabled:
            try refreshEnabledServiceIfNeeded(service)
        case .requiresApproval:
            throw InstallError.requiresApproval
        case .notRegistered, .notFound:
            try register(service)
        @unknown default:
            try register(service)
        }
    }

    static func reinstall() throws {
        let service = SMAppService.daemon(plistName: FanCtlHelperConstants.daemonPlistName)
        switch service.status {
        case .enabled:
            try service.unregister()
        case .requiresApproval:
            throw InstallError.requiresApproval
        case .notRegistered, .notFound:
            break
        @unknown default:
            break
        }

        UserDefaults.standard.removeObject(forKey: registeredHelperBuildKey)
        clearPendingBuild()
        try register(service)
    }

    private static func refreshEnabledServiceIfNeeded(_ service: SMAppService) throws {
        guard let currentBuild = currentBuildNumber else {
            return
        }

        let registeredBuild = UserDefaults.standard.string(forKey: registeredHelperBuildKey)
        let pendingBuild = UserDefaults.standard.string(forKey: pendingHelperBuildKey)

        if registeredBuild == currentBuild {
            clearPendingBuild()
            return
        }

        if pendingBuild == currentBuild {
            // A previous refresh reached the approval step. An enabled service now
            // means macOS completed that registration.
            rememberRegisteredBuild(currentBuild)
            clearPendingBuild()
            return
        }

        try service.unregister()
        rememberPendingBuild(currentBuild)
        try register(service)
    }

    private static func register(_ service: SMAppService) throws {
        try service.register()

        switch service.status {
        case .enabled:
            if let currentBuild = currentBuildNumber {
                rememberRegisteredBuild(currentBuild)
                clearPendingBuild()
            }
        case .requiresApproval:
            if let currentBuild = currentBuildNumber {
                rememberPendingBuild(currentBuild)
            }
            throw InstallError.requiresApproval
        case .notRegistered, .notFound:
            throw InstallError.registrationDidNotStart
        @unknown default:
            guard let currentBuild = currentBuildNumber else {
                return
            }
            rememberRegisteredBuild(currentBuild)
        }
    }

    private static var currentBuildNumber: String? {
        guard let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              !build.isEmpty else {
            return nil
        }
        return build
    }

    private static func rememberRegisteredBuild(_ build: String) {
        UserDefaults.standard.set(build, forKey: registeredHelperBuildKey)
    }

    private static func rememberPendingBuild(_ build: String) {
        UserDefaults.standard.set(build, forKey: pendingHelperBuildKey)
    }

    private static func clearPendingBuild() {
        UserDefaults.standard.removeObject(forKey: pendingHelperBuildKey)
    }
}

enum InstallError: LocalizedError {
    case requiresApproval
    case registrationDidNotStart

    var errorDescription: String? {
        switch self {
        case .requiresApproval:
            L10n.helperRequiresApproval
        case .registrationDidNotStart:
            L10n.helperRegistrationFailed
        }
    }
}
