import Dispatch
import Darwin
import FanCtlCore
import FanCtlHelperXPC
import Foundation
import ServiceManagement

@main
enum FanCtlLegacyCleanup {
    // The parent process allows 180 seconds. Keep one coherent child deadline
    // with enough margin for process termination and report decoding.
    private static let maximumExecutionDuration: TimeInterval = 120
    private static let operationTimeout: TimeInterval = 40
    private static let protocolProbeTimeout: TimeInterval = 3
    private static let launchctlQueryTimeout: TimeInterval = 5
    private static let launchctlTerminationGracePeriod: TimeInterval = 2
    private static let serviceStatePollInterval: TimeInterval = 0.1

    private enum LegacyLaunchDaemonState {
        case loaded(processIdentifier: pid_t?)
        case notLoaded
    }

    static func main() {
        do {
            guard Bundle.main.bundleIdentifier ==
                    FanCtlHelperConstants.legacyAppBundleIdentifier else {
                throw CleanupError.invalidIdentity
            }
            let deadline = CleanupDeadline(
                duration: maximumExecutionDuration
            )

            let daemonService = SMAppService.daemon(
                plistName: FanCtlHelperConstants.legacyDaemonPlistName
            )
            let loginService = SMAppService.mainApp
            let initialDaemonStatus = legacyStatus(daemonService.status)
            let initialLoginItemStatus = legacyStatus(loginService.status)
            let manualHelperInstallDetected =
                try legacyManualHelperInstallIsPresent(deadline: deadline)

            let statusOnly = CommandLine.arguments.contains("--status-only")
            let probeOnly = CommandLine.arguments.contains("--probe-only")
            let reportOnly = CommandLine.arguments.contains("--report-only")
            if reportOnly {
                try emitReport(FanCtlLegacyCleanupReport(
                    initialDaemonStatus: initialDaemonStatus,
                    initialLoginItemStatus: initialLoginItemStatus,
                    manualHelperInstallDetected:
                        manualHelperInstallDetected,
                    requiresActiveHelperRecovery: false
                ))
                return
            }
            if statusOnly || probeOnly {
                let probeResult: String
                if probeOnly, daemonService.status == .enabled {
                    let protocolName =
                        try legacyHelperUsesSequencedProtocol(
                            deadline: deadline
                        )
                            ? "sequenced"
                            : "unsequenced"
                    try pingLegacyHelper(deadline: deadline)
                    probeResult =
                        " xpc=reachable protocol=\(protocolName)"
                } else {
                    probeResult = ""
                }
                print(
                    "daemon=\(statusDescription(daemonService.status)) " +
                    "login=\(statusDescription(loginService.status))" +
                    " manualHelper=\(manualHelperInstallDetected)" +
                    probeResult
                )
                return
            }

            let plan = FanCtlLegacyCleanupPlanner.plan(
                daemonStatus: initialDaemonStatus,
                loginItemStatus: initialLoginItemStatus
            )
            let automaticAlreadyRestored =
                CommandLine.arguments.contains("--automatic-already-restored")
            if plan.restoresAutomatic && !automaticAlreadyRestored {
                try? restoreAutomaticFanControl(deadline: deadline)
            }
            if manualHelperInstallDetected && !automaticAlreadyRestored {
                if (try? verifyAutomaticFanControl(deadline: deadline)) == nil {
                    try? requestLegacyManualHelperAutomatic(
                        deadline: deadline
                    )
                }
            }
            let verifiesAutomatic =
                plan.unregistersDaemon ||
                manualHelperInstallDetected ||
                automaticAlreadyRestored
            var requiresActiveHelperRecovery =
                verifiesAutomatic &&
                (try? verifyAutomaticFanControl(deadline: deadline)) == nil

            if !requiresActiveHelperRecovery {
                if plan.unregistersDaemon {
                    let legacyProcessIdentifier =
                        try legacyDaemonProcessIdentifier(
                            deadline: deadline
                        )
                    try unregister(
                        daemonService,
                        name: "legacy fan helper",
                        deadline: deadline
                    )
                    try waitForLegacyDaemonToUnload(
                        processIdentifier: legacyProcessIdentifier,
                        deadline: deadline
                    )
                }
                if plan.unregistersLoginItem {
                    try unregister(
                        loginService,
                        name: "legacy login item",
                        deadline: deadline
                    )
                }

                if plan.unregistersDaemon {
                    try waitUntilInactive(
                        daemonService,
                        name: "legacy fan helper",
                        deadline: deadline
                    )
                }
                if plan.unregistersLoginItem {
                    try waitUntilInactive(
                        loginService,
                        name: "legacy login item",
                        deadline: deadline
                    )
                }

                // v0.3.0 and v0.3.1 did not sequence mutations. A manual
                // request already in flight can therefore finish after the
                // pre-unregister Automatic reply. Waiting for launchd to
                // remove the old daemon is the barrier; verify the complete
                // fan set again only after that barrier.
                if verifiesAutomatic,
                   (try? verifyAutomaticFanControl(deadline: deadline)) == nil {
                    requiresActiveHelperRecovery = true
                }
            }

            try emitReport(FanCtlLegacyCleanupReport(
                initialDaemonStatus: initialDaemonStatus,
                initialLoginItemStatus: initialLoginItemStatus,
                manualHelperInstallDetected: manualHelperInstallDetected,
                requiresActiveHelperRecovery: requiresActiveHelperRecovery
            ))
        } catch {
            fputs("MenuBar FanControl legacy cleanup failed: \(error)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    private static func restoreAutomaticFanControl(
        deadline: CleanupDeadline
    ) throws {
        if try legacyHelperUsesSequencedProtocol(deadline: deadline) {
            try performLegacyHelperRequest(
                interface: NSXPCInterface(
                    with: FanCtlHelperXPCProtocol.self
                ),
                operation: "restoring Automatic mode",
                deadline: deadline,
                cast: { $0 as? FanCtlHelperXPCProtocol }
            ) { proxy, reply in
                let uptime = DispatchTime.now().uptimeNanoseconds
                let sequence = Int64(min(uptime, UInt64(Int64.max)))
                proxy.setAutomatic(NSNumber(value: sequence), withReply: reply)
            }
        } else {
            try performLegacyHelperRequest(
                interface: NSXPCInterface(
                    with: FanCtlLegacyUnsequencedHelperXPCProtocol.self
                ),
                operation: "restoring Automatic mode with an older helper",
                deadline: deadline,
                cast: { $0 as? FanCtlLegacyUnsequencedHelperXPCProtocol }
            ) { proxy, reply in
                proxy.setAutomatic(withReply: reply)
            }
        }
    }

    private static func legacyHelperUsesSequencedProtocol(
        deadline: CleanupDeadline
    ) throws -> Bool {
        try deadline.check(
            operation: "probing the legacy helper protocol"
        )
        let connection = NSXPCConnection(
            machServiceName: FanCtlHelperConstants.legacyMachServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(
            with: FanCtlHelperXPCProtocol.self
        )

        let semaphore = DispatchSemaphore(value: 0)
        let state = LegacyProtocolProbeState()
        connection.interruptionHandler = {
            state.finish(.failure(CleanupError.legacyHelperUnavailable))
            semaphore.signal()
        }
        connection.invalidationHandler = {
            state.finish(.failure(CleanupError.legacyHelperUnavailable))
            semaphore.signal()
        }
        connection.resume()
        defer {
            connection.interruptionHandler = nil
            connection.invalidationHandler = nil
            connection.invalidate()
        }

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
            state.finish(.failure(CleanupError.legacyHelperUnavailable))
            semaphore.signal()
        }) as? FanCtlHelperXPCProtocol else {
            throw CleanupError.legacyHelperUnavailable
        }

        proxy.getVersion { version, _ in
            state.finish(.success(version.intValue >= 3))
            semaphore.signal()
        }

        guard semaphore.wait(
            timeout: try deadline.waitTimeout(
                maximum: protocolProbeTimeout,
                operation: "probing the legacy helper protocol"
            )
        ) == .success else {
            // v0.3.0 and v0.3.1 do not implement getVersion. Confirm that the
            // common ping selector is reachable before selecting their API.
            try pingLegacyHelper(deadline: deadline)
            return false
        }

        do {
            return try state.result().get()
        } catch {
            try pingLegacyHelper(deadline: deadline)
            return false
        }
    }

    private static func pingLegacyHelper(
        deadline: CleanupDeadline
    ) throws {
        try performLegacyHelperRequest(
            interface: NSXPCInterface(
                with: FanCtlLegacyUnsequencedHelperXPCProtocol.self
            ),
            operation: "contacting the legacy helper",
            deadline: deadline,
            cast: { $0 as? FanCtlLegacyUnsequencedHelperXPCProtocol }
        ) { proxy, reply in
            proxy.ping(withReply: reply)
        }
    }

    private static func requestLegacyManualHelperAutomatic(
        deadline: CleanupDeadline
    ) throws {
        try deadline.check(
            operation: "contacting the previous socket-based helper"
        )
        let socketPath =
            FanCtlHelperConstants.legacyManualHelperSocketPath
        guard pathExistsWithoutFollowingSymlinks(socketPath) else {
            throw CleanupError.legacyManualHelperUnavailable
        }

        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw CleanupError.legacyManualHelperUnavailable
        }
        defer { close(descriptor) }

        var noSigPipe: Int32 = 1
        guard setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSigPipe,
            socklen_t(MemoryLayout.size(ofValue: noSigPipe))
        ) == 0 else {
            throw CleanupError.legacyManualHelperUnavailable
        }

        let socketTimeoutInterval = try deadline.remaining(
            maximum: 3,
            operation: "contacting the previous socket-based helper"
        )
        let wholeSeconds = floor(socketTimeoutInterval)
        var socketTimeout = timeval(
            tv_sec: Int(wholeSeconds),
            tv_usec: Int32(
                max(
                    1,
                    min(
                        999_999,
                        (socketTimeoutInterval - wholeSeconds) * 1_000_000
                    )
                )
            )
        )
        guard setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_SNDTIMEO,
            &socketTimeout,
            socklen_t(MemoryLayout.size(ofValue: socketTimeout))
        ) == 0,
        setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &socketTimeout,
            socklen_t(MemoryLayout.size(ofValue: socketTimeout))
        ) == 0 else {
            throw CleanupError.legacyManualHelperUnavailable
        }

        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count <
                MemoryLayout.size(ofValue: address.sun_path) else {
            throw CleanupError.legacyManualHelperUnavailable
        }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(
                to: CChar.self,
                capacity: pathBytes.count + 1
            ) { buffer in
                for (index, byte) in pathBytes.enumerated() {
                    buffer[index] = CChar(bitPattern: byte)
                }
                buffer[pathBytes.count] = 0
            }
        }

        try connectLegacyManualSocket(
            descriptor: descriptor,
            address: &address,
            deadline: deadline
        )

        let command = Array("SET_AUTOMATIC\n".utf8)
        try command.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                throw CleanupError.legacyManualHelperUnavailable
            }
            var offset = 0
            while offset < rawBuffer.count {
                try deadline.check(
                    operation: "requesting Automatic mode from the previous socket-based helper"
                )
                let count = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    rawBuffer.count - offset
                )
                if count < 0, errno == EINTR {
                    continue
                }
                guard count > 0 else {
                    throw CleanupError.legacyManualHelperUnavailable
                }
                offset += count
            }
        }

        var response: [UInt8] = []
        response.reserveCapacity(64)
        while response.count < 512 {
            try deadline.check(
                operation: "reading the previous socket-based helper response"
            )
            var buffer = [UInt8](repeating: 0, count: 128)
            let count = Darwin.read(
                descriptor,
                &buffer,
                min(buffer.count, 512 - response.count)
            )
            if count < 0, errno == EINTR {
                continue
            }
            guard count > 0 else {
                break
            }
            response.append(contentsOf: buffer.prefix(Int(count)))
            if response.contains(0x0A) {
                break
            }
        }

        let value = String(decoding: response, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard value == "OK automatic" else {
            throw CleanupError.legacyManualHelperRejected(value)
        }
    }

    private static func connectLegacyManualSocket(
        descriptor: Int32,
        address: inout sockaddr_un,
        deadline: CleanupDeadline
    ) throws {
        let originalFlags = fcntl(descriptor, F_GETFL)
        guard originalFlags >= 0,
              fcntl(descriptor, F_SETFL, originalFlags | O_NONBLOCK) == 0 else {
            throw CleanupError.legacyManualHelperUnavailable
        }
        defer {
            _ = fcntl(descriptor, F_SETFL, originalFlags)
        }

        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(
                to: sockaddr.self,
                capacity: 1
            ) { socketAddress in
                Darwin.connect(
                    descriptor,
                    socketAddress,
                    socklen_t(MemoryLayout<sockaddr_un>.size)
                )
            }
        }
        if connectResult == 0 {
            return
        }
        guard errno == EINPROGRESS || errno == EAGAIN else {
            throw CleanupError.legacyManualHelperUnavailable
        }

        while true {
            var pollDescriptor = pollfd(
                fd: descriptor,
                events: Int16(POLLOUT),
                revents: 0
            )
            let pollTimeout = try deadline.pollTimeout(
                maximum: 3,
                operation: "connecting to the previous socket-based helper"
            )
            let result = Darwin.poll(&pollDescriptor, 1, pollTimeout)
            if result < 0, errno == EINTR {
                continue
            }
            guard result > 0 else {
                throw CleanupError.operationTimedOut(
                    "connecting to the previous socket-based helper"
                )
            }

            var socketError: Int32 = 0
            var socketErrorSize = socklen_t(
                MemoryLayout.size(ofValue: socketError)
            )
            guard getsockopt(
                descriptor,
                SOL_SOCKET,
                SO_ERROR,
                &socketError,
                &socketErrorSize
            ) == 0,
            socketError == 0 else {
                throw CleanupError.legacyManualHelperUnavailable
            }
            return
        }
    }

    private static func verifyAutomaticFanControl(
        deadline: CleanupDeadline
    ) throws {
        try deadline.check(operation: "verifying Automatic fan control")
        let smc = try SMCConnection()
        let expectedFanCount = try FanController(smc: smc).fanCount()
        guard expectedFanCount > 0 else {
            throw CleanupError.fanStateCouldNotBeVerified
        }

        let snapshot = try SensorReader(smc: smc)
            .snapshotStrict(scope: .complete)
        guard snapshot.fans.count == expectedFanCount,
              snapshot.fans.map(\.index) ==
                Array(0..<expectedFanCount) else {
            throw CleanupError.fanStateCouldNotBeVerified
        }
        let fanModes = try snapshot.fans.map { fan -> FanModeState in
            guard let rawMode = fan.mode else {
                throw CleanupError.fanStateCouldNotBeVerified
            }
            return FanModeState(
                fanIndex: fan.index,
                mode: ObservedFanMode(rawValue: rawMode)
            )
        }
        let status = FanAutomaticControlStatus(
            fans: fanModes,
            forceTestMode: snapshot.fanTestMode
        )
        guard status.isFullyAutomatic else {
            throw CleanupError.fanStateIsNotAutomatic
        }
        try deadline.check(operation: "verifying Automatic fan control")
    }

    private static func performLegacyHelperRequest<Proxy>(
        interface: NSXPCInterface,
        operation: String,
        deadline: CleanupDeadline,
        cast: (Any) -> Proxy?,
        _ invoke: (
            Proxy,
            @escaping (NSString?, NSString?) -> Void
        ) -> Void
    ) throws {
        try deadline.check(operation: operation)
        let connection = NSXPCConnection(
            machServiceName: FanCtlHelperConstants.legacyMachServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = interface

        let semaphore = DispatchSemaphore(value: 0)
        let state = SynchronousReplyState()
        connection.interruptionHandler = {
            state.finish(.failure(CleanupError.legacyHelperUnavailable))
            semaphore.signal()
        }
        connection.invalidationHandler = {
            state.finish(.failure(CleanupError.legacyHelperUnavailable))
            semaphore.signal()
        }
        connection.resume()
        defer {
            connection.interruptionHandler = nil
            connection.invalidationHandler = nil
            connection.invalidate()
        }

        let remoteProxy = connection.remoteObjectProxyWithErrorHandler({ _ in
            state.finish(.failure(CleanupError.legacyHelperUnavailable))
            semaphore.signal()
        })
        guard let proxy = cast(remoteProxy) else {
            throw CleanupError.legacyHelperUnavailable
        }

        invoke(proxy) { response, errorMessage in
            if response != nil {
                state.finish(.success(()))
            } else if let errorMessage {
                state.finish(.failure(
                    CleanupError.automaticRestoreRejected(errorMessage as String)
                ))
            } else {
                state.finish(.failure(CleanupError.invalidLegacyHelperResponse))
            }
            semaphore.signal()
        }

        guard semaphore.wait(
            timeout: try deadline.waitTimeout(
                maximum: operationTimeout,
                operation: operation
            )
        ) == .success else {
            throw CleanupError.operationTimedOut(operation)
        }
        try state.result().get()
    }

    private static func unregister(
        _ service: SMAppService,
        name: String,
        deadline: CleanupDeadline
    ) throws {
        try deadline.check(operation: "unregistering \(name)")
        let semaphore = DispatchSemaphore(value: 0)
        let state = SynchronousReplyState()
        service.unregister { error in
            if let error {
                state.finish(.failure(error))
            } else {
                state.finish(.success(()))
            }
            semaphore.signal()
        }

        guard semaphore.wait(
            timeout: try deadline.waitTimeout(
                maximum: operationTimeout,
                operation: "unregistering \(name)"
            )
        ) == .success else {
            throw CleanupError.operationTimedOut("unregistering \(name)")
        }
        try state.result().get()
    }

    private static func waitUntilInactive(
        _ service: SMAppService,
        name: String,
        deadline: CleanupDeadline
    ) throws {
        while !isInactive(service.status) {
            try deadline.sleep(
                maximum: serviceStatePollInterval,
                operation: "waiting for \(name) to become inactive"
            )
        }
    }

    private static func waitForLegacyDaemonToUnload(
        processIdentifier: pid_t?,
        deadline: CleanupDeadline
    ) throws {
        while true {
            switch try launchDaemonState(
                identifier: FanCtlHelperConstants.legacyMachServiceName,
                operation: "waiting for the legacy fan helper to unload",
                deadline: deadline
            ) {
            case .notLoaded:
                break
            case .loaded:
                try deadline.sleep(
                    maximum: serviceStatePollInterval,
                    operation: "waiting for the legacy fan helper to unload"
                )
                continue
            }
            break
        }

        guard let processIdentifier else {
            return
        }
        while processIsRunning(processIdentifier) {
            try deadline.sleep(
                maximum: serviceStatePollInterval,
                operation: "waiting for the legacy fan helper process to exit"
            )
        }
    }

    private static func legacyDaemonProcessIdentifier(
        deadline: CleanupDeadline
    ) throws -> pid_t? {
        switch try launchDaemonState(
            identifier: FanCtlHelperConstants.legacyMachServiceName,
            operation: "inspecting the legacy fan helper process",
            deadline: deadline
        ) {
        case .loaded(let processIdentifier):
            return processIdentifier
        case .notLoaded:
            return nil
        }
    }

    private static func emitReport(
        _ report: FanCtlLegacyCleanupReport
    ) throws {
        let data = try JSONEncoder().encode(report)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    }

    private static func legacyManualHelperInstallIsPresent(
        deadline: CleanupDeadline
    ) throws -> Bool {
        if [
            FanCtlHelperConstants.legacyManualHelperExecutablePath,
            FanCtlHelperConstants.legacyManualHelperPlistPath,
            FanCtlHelperConstants.legacyManualHelperSocketPath,
            FanCtlHelperConstants.legacyManualHelperLogPath
        ].contains(where: pathExistsWithoutFollowingSymlinks) {
            return true
        }

        switch try launchDaemonState(
            identifier: FanCtlHelperConstants.legacyManualHelperIdentifier,
            operation: "checking the previous socket-based helper",
            deadline: deadline
        ) {
        case .loaded:
            return true
        case .notLoaded:
            return false
        }
    }

    private static func launchDaemonState(
        identifier: String,
        operation: String,
        deadline: CleanupDeadline
    ) throws -> LegacyLaunchDaemonState {
        try deadline.check(operation: operation)
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = [
            "print",
            "system/\(identifier)"
        ]
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        let termination = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            termination.signal()
        }
        do {
            try process.run()
        } catch {
            throw CleanupError.launchDaemonQueryFailed(
                operation: operation,
                detail: error.localizedDescription
            )
        }

        guard termination.wait(
            timeout: try deadline.waitTimeout(
                maximum: launchctlQueryTimeout,
                operation: operation
            )
        ) == .success else {
            process.terminate()
            _ = termination.wait(
                timeout: .now() + launchctlTerminationGracePeriod
            )
            process.terminationHandler = nil
            throw CleanupError.operationTimedOut(operation)
        }
        process.terminationHandler = nil

        let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let detail = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if process.terminationReason == .exit,
           process.terminationStatus == 0 {
            let output =
                outputPipe.fileHandleForReading.readDataToEndOfFile()
            return .loaded(
                processIdentifier: launchDaemonProcessIdentifier(
                    from: output
                )
            )
        }
        if process.terminationReason == .exit,
           process.terminationStatus == 113,
           detail.localizedCaseInsensitiveContains(
               "could not find service"
           ) {
            return .notLoaded
        }
        throw CleanupError.launchDaemonQueryFailed(
            operation: operation,
            detail: detail.isEmpty
                ? "launchctl exited with status \(process.terminationStatus)"
                : detail
        )
    }

    private static func launchDaemonProcessIdentifier(
        from launchctlOutput: Data
    ) -> pid_t? {
        guard let output = String(
            data: launchctlOutput,
            encoding: .utf8
        ) else {
            return nil
        }
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line
                .trimmingCharacters(in: .whitespaces)
                .split(
                    separator: "=",
                    maxSplits: 1,
                    omittingEmptySubsequences: false
                )
            guard fields.count == 2,
                  fields[0].trimmingCharacters(in: .whitespaces) == "pid",
                  let value = pid_t(
                    fields[1].trimmingCharacters(in: .whitespaces)
                  ),
                  value > 0 else {
                continue
            }
            return value
        }
        return nil
    }

    private static func processIsRunning(
        _ processIdentifier: pid_t
    ) -> Bool {
        if kill(processIdentifier, 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    private static func pathExistsWithoutFollowingSymlinks(
        _ path: String
    ) -> Bool {
        var information = stat()
        return lstat(path, &information) == 0
    }

    private static func isInactive(_ status: SMAppService.Status) -> Bool {
        switch status {
        case .notRegistered, .notFound:
            true
        case .enabled, .requiresApproval:
            false
        @unknown default:
            false
        }
    }

    private static func legacyStatus(
        _ status: SMAppService.Status
    ) -> FanCtlLegacyServiceStatus {
        switch status {
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notRegistered, .notFound:
            .inactive
        @unknown default:
            .requiresApproval
        }
    }

    private static func statusDescription(
        _ status: SMAppService.Status
    ) -> String {
        switch status {
        case .notRegistered:
            "notRegistered"
        case .enabled:
            "enabled"
        case .requiresApproval:
            "requiresApproval"
        case .notFound:
            "notFound"
        @unknown default:
            "unknown"
        }
    }
}

private struct CleanupDeadline: Sendable {
    private let uptimeNanoseconds: UInt64

    init(duration: TimeInterval) {
        precondition(duration.isFinite && duration > 0)
        let now = DispatchTime.now().uptimeNanoseconds
        let durationNanoseconds = UInt64(
            min(duration, 3_600) * 1_000_000_000
        )
        uptimeNanoseconds =
            now > UInt64.max - durationNanoseconds
                ? UInt64.max
                : now + durationNanoseconds
    }

    func check(operation: String) throws {
        guard DispatchTime.now().uptimeNanoseconds < uptimeNanoseconds else {
            throw CleanupError.operationTimedOut(operation)
        }
    }

    func remaining(
        maximum: TimeInterval,
        operation: String
    ) throws -> TimeInterval {
        precondition(maximum.isFinite && maximum > 0)
        let now = DispatchTime.now().uptimeNanoseconds
        guard now < uptimeNanoseconds else {
            throw CleanupError.operationTimedOut(operation)
        }
        let remainingNanoseconds = uptimeNanoseconds - now
        return min(
            maximum,
            Double(remainingNanoseconds) / 1_000_000_000
        )
    }

    func waitTimeout(
        maximum: TimeInterval,
        operation: String
    ) throws -> DispatchTime {
        let now = DispatchTime.now().uptimeNanoseconds
        let interval = try remaining(
            maximum: maximum,
            operation: operation
        )
        let intervalNanoseconds = max(
            UInt64(1),
            UInt64(interval * 1_000_000_000)
        )
        let candidate =
            now > UInt64.max - intervalNanoseconds
                ? UInt64.max
                : now + intervalNanoseconds
        return DispatchTime(
            uptimeNanoseconds: min(uptimeNanoseconds, candidate)
        )
    }

    func pollTimeout(
        maximum: TimeInterval,
        operation: String
    ) throws -> Int32 {
        let interval = try remaining(
            maximum: maximum,
            operation: operation
        )
        return Int32(
            min(
                Double(Int32.max),
                max(1, ceil(interval * 1_000))
            )
        )
    }

    func sleep(
        maximum: TimeInterval,
        operation: String
    ) throws {
        Thread.sleep(
            forTimeInterval: try remaining(
                maximum: maximum,
                operation: operation
            )
        )
        try check(operation: operation)
    }
}

private final class SynchronousReplyState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedResult: Result<Void, Error>?

    func finish(_ result: Result<Void, Error>) {
        lock.lock()
        if storedResult == nil {
            storedResult = result
        }
        lock.unlock()
    }

    func result() throws -> Result<Void, Error> {
        lock.lock()
        defer { lock.unlock() }
        guard let storedResult else {
            throw CleanupError.invalidLegacyHelperResponse
        }
        return storedResult
    }
}

private final class LegacyProtocolProbeState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedResult: Result<Bool, Error>?

    func finish(_ result: Result<Bool, Error>) {
        lock.lock()
        if storedResult == nil {
            storedResult = result
        }
        lock.unlock()
    }

    func result() throws -> Result<Bool, Error> {
        lock.lock()
        defer { lock.unlock() }
        guard let storedResult else {
            throw CleanupError.invalidLegacyHelperResponse
        }
        return storedResult
    }
}

private enum CleanupError: LocalizedError {
    case invalidIdentity
    case legacyHelperUnavailable
    case legacyManualHelperUnavailable
    case legacyManualHelperRejected(String)
    case launchDaemonQueryFailed(operation: String, detail: String)
    case automaticRestoreRejected(String)
    case invalidLegacyHelperResponse
    case fanStateCouldNotBeVerified
    case fanStateIsNotAutomatic
    case operationTimedOut(String)

    var errorDescription: String? {
        switch self {
        case .invalidIdentity:
            "The cleanup bridge does not have the legacy application identity."
        case .legacyHelperUnavailable:
            "The legacy fan helper could not be reached."
        case .legacyManualHelperUnavailable:
            "The previous socket-based fan helper could not be reached."
        case .legacyManualHelperRejected(let message):
            "The previous socket-based fan helper rejected Automatic mode: \(message)"
        case .launchDaemonQueryFailed(let operation, let detail):
            "Failed while \(operation): \(detail)"
        case .automaticRestoreRejected(let message):
            "The legacy fan helper rejected Automatic mode: \(message)"
        case .invalidLegacyHelperResponse:
            "The legacy fan helper returned an invalid response."
        case .fanStateCouldNotBeVerified:
            "The current fan state could not be verified."
        case .fanStateIsNotAutomatic:
            "The fans are not in Automatic mode, so the legacy helper was not removed."
        case .operationTimedOut(let operation):
            "Timed out while \(operation)."
        }
    }
}
