import FanCtlHelperXPC
import Foundation
import ServiceManagement

enum FanCtlHelperClient {
    static let fanCommandTimeout: TimeInterval = 45.0
    static let automaticFallbackTimeout: TimeInterval = 5.0

    enum Error: LocalizedError {
        case unavailable
        case rejected(String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .unavailable:
                L10n.helperUnavailable
            case .rejected(let message):
                message
            case .invalidResponse:
                L10n.invalidHelperResponse
            }
        }
    }

    static func waitUntilAvailable(timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        var lastError: Swift.Error = Error.unavailable

        while Date() < deadline {
            do {
                _ = try await send("PING")
                return
            } catch {
                lastError = error
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        throw lastError
    }

    static func send(_ command: String, timeout: TimeInterval = 5.0) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await sendWithoutTimeout(command)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw Error.unavailable
            }

            guard let result = try await group.next() else {
                throw Error.unavailable
            }
            group.cancelAll()
            return result
        }
    }

    private static func sendWithoutTimeout(_ command: String) async throws -> String {
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
                        state.finish(.failure(Error.rejected(errorMessage as String)))
                    } else {
                        state.finish(.failure(Error.invalidResponse))
                    }
                }

                connection.resume()
                guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                    state.finish(.failure(Error.rejected(error.localizedDescription)))
                }) as? FanCtlHelperXPCProtocol else {
                    state.finish(.failure(Error.unavailable))
                    return
                }

                do {
                    switch command {
                    case "PING":
                        proxy.ping(withReply: reply)
                    case "SET_AUTOMATIC":
                        proxy.setAutomatic(withReply: reply)
                    case "SET_MAXIMUM":
                        proxy.setMaximum(withReply: reply)
                    default:
                        if command.hasPrefix("SET_RPM ") {
                            let rawRPM = String(command.dropFirst("SET_RPM ".count))
                            guard let rpm = Double(rawRPM), rpm.isFinite else {
                                throw Error.rejected(L10n.invalidHelperResponse)
                            }
                            proxy.setRPM(NSNumber(value: rpm), withReply: reply)
                        } else {
                            throw Error.rejected(L10n.invalidHelperResponse)
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
}

private final class XPCConnectionHandle: @unchecked Sendable {
    private let lock = NSLock()
    private let connection: NSXPCConnection

    init(_ connection: NSXPCConnection) {
        self.connection = connection
    }

    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
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
            rememberRegisteredBuild(currentBuild)
            clearPendingBuild()
            return
        }

        rememberRegisteredBuild(currentBuild)
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
