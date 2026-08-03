import FanCtlCore
import FanCtlHelperXPC
import Darwin
import Dispatch
import Foundation
import Security

private final class FanCtlHelperService: NSObject, FanCtlHelperXPCProtocol, @unchecked Sendable {
    private static let fastAutomaticRecoveryAttempts = 3
    private static let fastAutomaticRecoveryRetryInterval: TimeInterval = 5
    private static let slowAutomaticRecoveryRetryInterval: TimeInterval = 60
    private static let startupAutomaticRecoveryDelay: TimeInterval = 1

    private let mutationLock = NSLock()
    private let watchdogQueue = DispatchQueue(
        label: "\(FanCtlHelperConstants.machServiceName).manual-lease"
    )
    private var leaseWatchdog: DispatchSourceTimer?
    private var leaseWatchdogGeneration: UInt64 = 0
    private var manualLeaseDeadline: DispatchTime?
    private var automaticRecoveryPending = true
    private var automaticRecoveryAttempts = 0
    private var nextAutomaticRecoveryAttempt = DispatchTime.now()
    private var highestMutationSequence = Int64.min

    override init() {
        super.init()

        mutationLock.lock()
        nextAutomaticRecoveryAttempt = deadline(
            after: Self.startupAutomaticRecoveryDelay
        )
        rescheduleLeaseWatchdogLocked()
        mutationLock.unlock()
    }

    deinit {
        mutationLock.lock()
        cancelLeaseWatchdogLocked()
        mutationLock.unlock()
    }

    func ping(withReply reply: @escaping (NSString?, NSString?) -> Void) {
        reply("pong", nil)
    }

    func getVersion(withReply reply: @escaping (NSNumber, NSString) -> Void) {
        reply(
            NSNumber(value: FanCtlHelperConstants.protocolVersion),
            enclosingApplicationBuild() as NSString
        )
    }

    func renewManualControlLease(
        _ sequence: NSNumber,
        withReply reply: @escaping (NSString?, NSString?) -> Void
    ) {
        completeMutation(sequence: sequence, reply) {
            try renewManualControlLease()
            return "manual lease renewed"
        }
    }

    func setAutomatic(_ sequence: NSNumber, withReply reply: @escaping (NSString?, NSString?) -> Void) {
        completeMutation(sequence: sequence, reply) {
            do {
                try setAutomatic()
            } catch {
                scheduleAutomaticRecoveryAfterFailedAttempt()
                throw error
            }
            return "automatic"
        }
    }

    func setMaximum(_ sequence: NSNumber, withReply reply: @escaping (NSString?, NSString?) -> Void) {
        completeMutation(sequence: sequence, reply) {
            try setMaximum()
            return "maximum"
        }
    }

    func setRPM(
        _ rpm: NSNumber,
        sequence: NSNumber,
        withReply reply: @escaping (NSString?, NSString?) -> Void
    ) {
        completeMutation(sequence: sequence, reply) {
            let value = try validatedRPM(rpm)
            try setRPM(Double(value))
            return "rpm \(value)"
        }
    }

    func removeLegacyManualHelperInstall(
        _ sequence: NSNumber,
        withReply reply: @escaping (NSString?, NSString?) -> Void
    ) {
        completeMutation(sequence: sequence, reply) {
            do {
                guard LegacyManualHelperInstall.isPresent else {
                    return "legacy helper absent"
                }
                try setAutomatic()
                try LegacyManualHelperInstall.remove {
                    try setAutomatic()
                }
                return "legacy helper removed"
            } catch {
                scheduleAutomaticRecoveryAfterFailedAttempt()
                throw error
            }
        }
    }

    private func completeMutation(
        sequence: NSNumber,
        _ reply: @escaping (NSString?, NSString?) -> Void,
        operation: () throws -> String
    ) {
        mutationLock.lock()
        let result = Result {
            let validatedSequence = try validateMutationSequence(sequence)
            guard validatedSequence > highestMutationSequence else {
                throw FanCtlHelperError.staleMutationSequence(
                    received: validatedSequence,
                    latest: highestMutationSequence
                )
            }
            highestMutationSequence = validatedSequence
            return try operation()
        }
        mutationLock.unlock()

        switch result {
        case .success(let response):
            reply(response as NSString, nil)
        case .failure(let error):
            let failure = wireFailure(for: error)
            reply(nil, FanCtlHelperWire.encodeFailure(code: failure.code, message: failure.message) as NSString)
        }
    }

    private func validateMutationSequence(_ sequence: NSNumber) throws -> Int64 {
        guard let value = Int64(sequence.stringValue), value >= 0 else {
            throw FanCtlHelperError.invalidMutationSequence(sequence.stringValue)
        }
        return value
    }

    private func validatedRPM(_ rpm: NSNumber) throws -> Int {
        let value = rpm.doubleValue
        guard value.isFinite,
              value.rounded(.towardZero) == value,
              value >= Double(FanCtlHelperConstants.minimumRPM),
              value <= Double(FanCtlHelperConstants.maximumEncodedRPM) else {
            throw FanCtlHelperError.invalidRPM(rpm.stringValue)
        }

        // The bounds above make this conversion safe on every supported architecture.
        return Int(value)
    }

    private func enclosingApplicationBuild() -> String {
        if let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
           !build.isEmpty {
            return build
        }

        var candidate = URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
        while candidate.path != "/" {
            if candidate.pathExtension == "app",
               let bundle = Bundle(url: candidate),
               let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
               !build.isEmpty {
                return build
            }
            candidate.deleteLastPathComponent()
        }
        return "unknown"
    }

    private func renewManualControlLease() throws {
        let now = DispatchTime.now()
        guard let currentDeadline = manualLeaseDeadline,
              currentDeadline.uptimeNanoseconds > now.uptimeNanoseconds,
              !automaticRecoveryPending else {
            if manualLeaseDeadline != nil {
                manualLeaseDeadline = nil
                automaticRecoveryPending = true
                automaticRecoveryAttempts = 0
                nextAutomaticRecoveryAttempt = now
                rescheduleLeaseWatchdogLocked()
            }
            throw FanCtlHelperError.manualLeaseInactive
        }

        manualLeaseDeadline = deadline(
            after: FanCtlHelperConstants.manualControlLeaseDuration,
            from: now
        )
        rescheduleLeaseWatchdogLocked()
    }

    private func armManualControlLease() {
        manualLeaseDeadline = deadline(
            after: FanCtlHelperConstants.manualControlLeaseDuration
        )
        automaticRecoveryPending = false
        automaticRecoveryAttempts = 0
        rescheduleLeaseWatchdogLocked()
    }

    private func clearManualControlLease() {
        manualLeaseDeadline = nil
        automaticRecoveryPending = false
        automaticRecoveryAttempts = 0
        rescheduleLeaseWatchdogLocked()
    }

    private func scheduleAutomaticRecoveryAfterFailedAttempt() {
        manualLeaseDeadline = nil
        automaticRecoveryPending = true
        automaticRecoveryAttempts = 1
        nextAutomaticRecoveryAttempt = deadline(
            after: Self.fastAutomaticRecoveryRetryInterval
        )
        rescheduleLeaseWatchdogLocked()
    }

    private func deadline(
        after interval: TimeInterval,
        from start: DispatchTime = .now()
    ) -> DispatchTime {
        start + .milliseconds(Int(interval * 1_000))
    }

    private func rescheduleLeaseWatchdogLocked() {
        cancelLeaseWatchdogLocked()

        guard let nextDeadline = nextLeaseWatchdogDeadlineLocked() else {
            // No active lease and no recovery work: retain no timer at all so the
            // privileged helper stays completely idle.
            return
        }

        let generation = leaseWatchdogGeneration
        let watchdog = DispatchSource.makeTimerSource(queue: watchdogQueue)
        watchdog.schedule(deadline: nextDeadline, leeway: .milliseconds(250))
        watchdog.setEventHandler { [weak self] in
            self?.handleLeaseWatchdog(generation: generation)
        }
        leaseWatchdog = watchdog
        watchdog.resume()
    }

    private func cancelLeaseWatchdogLocked() {
        // Cancellation can race an event that is already queued. Advancing the
        // generation makes that event a no-op even if it runs later.
        leaseWatchdogGeneration &+= 1
        let watchdog = leaseWatchdog
        leaseWatchdog = nil
        watchdog?.cancel()
    }

    private func nextLeaseWatchdogDeadlineLocked() -> DispatchTime? {
        guard automaticRecoveryPending else {
            return manualLeaseDeadline
        }
        guard let manualLeaseDeadline else {
            return nextAutomaticRecoveryAttempt
        }
        return nextAutomaticRecoveryAttempt.uptimeNanoseconds < manualLeaseDeadline.uptimeNanoseconds
            ? nextAutomaticRecoveryAttempt
            : manualLeaseDeadline
    }

    private func handleLeaseWatchdog(generation: UInt64) {
        var logMessages: [String] = []

        mutationLock.lock()
        guard generation == leaseWatchdogGeneration else {
            mutationLock.unlock()
            return
        }
        cancelLeaseWatchdogLocked()

        let now = DispatchTime.now()
        if let currentDeadline = manualLeaseDeadline,
           currentDeadline.uptimeNanoseconds <= now.uptimeNanoseconds {
            manualLeaseDeadline = nil
            automaticRecoveryPending = true
            automaticRecoveryAttempts = 0
            nextAutomaticRecoveryAttempt = now
            logMessages.append(
                "MenuBar FanControl helper: manual-control lease expired; restoring automatic fan control."
            )
        }

        if automaticRecoveryPending,
           now.uptimeNanoseconds >= nextAutomaticRecoveryAttempt.uptimeNanoseconds {
            let attempt = automaticRecoveryAttempts + 1
            do {
                try setAutomatic()
                logMessages.append(
                    "MenuBar FanControl helper: automatic fan-control recovery succeeded on attempt \(attempt)."
                )
            } catch {
                automaticRecoveryAttempts = attempt
                let retryInterval: TimeInterval
                if attempt < Self.fastAutomaticRecoveryAttempts {
                    retryInterval = Self.fastAutomaticRecoveryRetryInterval
                    logMessages.append(
                        "MenuBar FanControl helper: automatic fan-control recovery attempt \(attempt)/\(Self.fastAutomaticRecoveryAttempts) failed: \(error.localizedDescription)"
                    )
                } else {
                    retryInterval = Self.slowAutomaticRecoveryRetryInterval
                    let phase = attempt == Self.fastAutomaticRecoveryAttempts
                        ? "fast recovery exhausted; switching to periodic recovery"
                        : "periodic recovery attempt \(attempt) failed"
                    logMessages.append(
                        "MenuBar FanControl helper: \(phase): \(error.localizedDescription)"
                    )
                }
                automaticRecoveryPending = true
                // Base the backoff on completion rather than the pre-attempt
                // timestamp. A slow firmware timeout must not cause the next
                // recovery attempt to fire immediately.
                nextAutomaticRecoveryAttempt = deadline(after: retryInterval)
            }
        }
        rescheduleLeaseWatchdogLocked()
        mutationLock.unlock()

        for message in logMessages {
            NSLog("%@", message)
        }
    }

    private func setAutomatic() throws {
        let smc = try SMCConnection()
        let fanCount = try requiredFanCount(smc: smc)
        let controller = FanController(smc: smc)
        var failures: [String] = []

        // Automatic is the safety state, so continue attempting every fan even when
        // one fan fails. The batch API preserves per-fan failure details.
        do {
            try controller.setAutomatic()
        } catch {
            failures.append(error.localizedDescription)
        }

        let verificationFailures = automaticVerificationFailures(
            smc: smc,
            expectedFanCount: fanCount
        )
        guard verificationFailures.isEmpty else {
            failures.append(contentsOf: verificationFailures)
            throw FanCtlHelperError.incompleteOperation(operation: "set automatic", failures: failures)
        }
        clearManualControlLease()
    }

    private func setMaximum() throws {
        let smc = try SMCConnection()
        let fans = try enumerateFansForManualControl(smc: smc)
        try applyManualTransaction(smc: smc, fans: fans) { fan in
            guard let maximumRPM = fan.maximumRPM else {
                throw FanCtlHelperError.invalidFanConfiguration(
                    fanIndex: fan.index,
                    detail: "maximum RPM was not preflighted"
                )
            }
            return maximumRPM
        }
        armManualControlLease()
    }

    private func setRPM(_ rpm: Double) throws {
        let smc = try SMCConnection()
        let fans = try enumerateFansForManualControl(smc: smc)
        for fan in fans {
            guard let minimumRPM = fan.minimumRPM,
                  let maximumRPM = fan.maximumRPM else {
                throw FanCtlHelperError.invalidFanConfiguration(
                    fanIndex: fan.index,
                    detail: "RPM range was not preflighted"
                )
            }
            guard (minimumRPM...maximumRPM).contains(rpm) else {
                throw FanCtlHelperError.rpmOutsideFanRange(
                    requested: rpm,
                    fanIndex: fan.index,
                    minimum: minimumRPM,
                    maximum: maximumRPM
                )
            }
        }
        try applyManualTransaction(smc: smc, fans: fans) { _ in rpm }
        armManualControlLease()
    }

    private func applyManualTransaction(
        smc: SMCConnection,
        fans: [ControllableFan],
        requestedRPM: (ControllableFan) throws -> Double
    ) throws {
        let controller = FanController(smc: smc)
        var expectedTargets: [Int: Double] = [:]

        do {
            for fan in fans {
                let result: FanControlResult
                do {
                    result = try controller.setManual(
                        fanIndex: fan.index,
                        rpm: requestedRPM(fan)
                    )
                } catch {
                    throw FanCtlHelperError.fanOperationFailed(
                        operation: "set manual RPM",
                        fanIndex: fan.index,
                        detail: error.localizedDescription
                    )
                }
                expectedTargets[fan.index] = result.appliedRPM
            }

            let verificationFailures = manualVerificationFailures(
                smc: smc,
                fans: fans,
                expectedTargets: expectedTargets
            )
            guard verificationFailures.isEmpty else {
                throw FanCtlHelperError.incompleteOperation(
                    operation: "verify manual RPM",
                    failures: verificationFailures
                )
            }
        } catch {
            let recoveryFailures = recoverAutomatic(controller: controller, smc: smc, fans: fans)
            guard recoveryFailures.isEmpty else {
                scheduleAutomaticRecoveryAfterFailedAttempt()
                throw FanCtlHelperError.automaticRecoveryFailed(
                    primary: error.localizedDescription,
                    failures: recoveryFailures
                )
            }
            clearManualControlLease()
            throw error
        }
    }

    private func recoverAutomatic(
        controller: FanController,
        smc: SMCConnection,
        fans: [ControllableFan]
    ) -> [String] {
        var failures: [String] = []
        do {
            try controller.setAutomatic()
        } catch {
            failures.append(error.localizedDescription)
        }
        let verificationFailures = automaticVerificationFailures(
            smc: smc,
            expectedFanCount: fans.count
        )
        guard !verificationFailures.isEmpty else {
            return []
        }
        failures.append(contentsOf: verificationFailures)
        return failures
    }

    private func requiredFanCount(smc: SMCConnection) throws -> Int {
        let count: Int
        do {
            count = try FanController(smc: smc).fanCount()
        } catch {
            throw FanCtlHelperError.invalidFanCount(error.localizedDescription)
        }
        guard count > 0 else {
            throw FanCtlHelperError.invalidFanCount("0")
        }
        return count
    }

    private func enumerateFansForManualControl(smc: SMCConnection) throws -> [ControllableFan] {
        let count = try requiredFanCount(smc: smc)
        var fans: [ControllableFan] = []
        fans.reserveCapacity(count)

        for index in 0..<count {
            let modeKey = try requiredModeKey(smc: smc, fanIndex: index)
            let targetKey = "F\(index)Tg"
            let target = try requiredValue(smc: smc, key: targetKey, fanIndex: index)
            let hasSupportedTargetEncoding =
                (target.dataType == "flt " && target.dataSize == 4) ||
                (target.dataType == "fpe2" && target.dataSize == 2)
            guard hasSupportedTargetEncoding else {
                throw FanCtlHelperError.invalidFanConfiguration(
                    fanIndex: index,
                    detail: "unsupported \(targetKey) encoding \(target.dataType)/\(target.dataSize)"
                )
            }

            let minimum = try requiredNumericValue(smc: smc, key: "F\(index)Mn", fanIndex: index)
            let maximum = try requiredNumericValue(smc: smc, key: "F\(index)Mx", fanIndex: index)
            guard minimum >= 0,
                  maximum >= Double(FanCtlHelperConstants.minimumRPM),
                  minimum <= maximum,
                  maximum <= Double(FanCtlHelperConstants.maximumEncodedRPM) else {
                throw FanCtlHelperError.invalidFanConfiguration(
                    fanIndex: index,
                    detail: "invalid RPM range \(minimum)...\(maximum)"
                )
            }

            fans.append(ControllableFan(
                index: index,
                modeKey: modeKey,
                targetKey: targetKey,
                minimumRPM: minimum,
                maximumRPM: maximum
            ))
        }

        guard fans.count == count else {
            throw FanCtlHelperError.invalidFanCount("expected \(count), enumerated \(fans.count)")
        }
        return fans
    }

    private func requiredModeKey(smc: SMCConnection, fanIndex: Int) throws -> String {
        var failures: [String] = []
        for key in ["F\(fanIndex)md", "F\(fanIndex)Md"] {
            do {
                let value = try smc.read(key)
                let hasSupportedModeEncoding =
                    (value.dataType == "ui8 " && value.dataSize == 1) ||
                    (value.dataType == "ui16" && value.dataSize == 2) ||
                    (value.dataType == "ui32" && value.dataSize == 4)
                guard hasSupportedModeEncoding,
                      let mode = value.numericValue,
                      mode.isFinite,
                      mode.rounded(.towardZero) == mode,
                      mode >= 0,
                      mode <= Double(UInt8.max) else {
                    failures.append("\(key): unsupported or malformed value")
                    continue
                }
                return key
            } catch {
                failures.append("\(key): \(error.localizedDescription)")
            }
        }

        throw FanCtlHelperError.missingFanMode(fanIndex: fanIndex, failures: failures)
    }

    private func requiredValue(
        smc: SMCConnection,
        key: String,
        fanIndex: Int?
    ) throws -> SMCValue {
        do {
            return try smc.read(key)
        } catch {
            throw FanCtlHelperError.requiredKeyUnavailable(
                key: key,
                fanIndex: fanIndex,
                detail: error.localizedDescription
            )
        }
    }

    private func requiredNumericValue(
        smc: SMCConnection,
        key: String,
        fanIndex: Int?
    ) throws -> Double {
        let value = try requiredValue(smc: smc, key: key, fanIndex: fanIndex)
        guard let numericValue = value.numericValue, numericValue.isFinite else {
            throw FanCtlHelperError.requiredKeyUnavailable(
                key: key,
                fanIndex: fanIndex,
                detail: "unsupported or malformed \(value.dataType)/\(value.dataSize) value"
            )
        }
        return numericValue
    }

    private func automaticVerificationFailures(
        smc: SMCConnection,
        expectedFanCount: Int
    ) -> [String] {
        do {
            let status = try FanController(smc: smc).automaticControlStatus()
            var failures: [String] = []
            if status.fans.count != expectedFanCount {
                failures.append(
                    "fan count changed from \(expectedFanCount) to \(status.fans.count) during verification"
                )
            }
            for fan in status.fans where !fan.mode.isSystemControlled {
                failures.append(
                    "fan \(fan.fanIndex): mode is \(fan.mode.rawValue), expected 0 or 3"
                )
            }
            if let forceTestMode = status.forceTestMode, forceTestMode != 0 {
                failures.append("Ftst: expected 0, received \(forceTestMode)")
            }
            if failures.isEmpty, !status.isFullyAutomatic {
                failures.append("automatic control status was not fully recovered")
            }
            return failures
        } catch {
            return ["could not verify automatic control status: \(error.localizedDescription)"]
        }
    }

    private func manualVerificationFailures(
        smc: SMCConnection,
        fans: [ControllableFan],
        expectedTargets: [Int: Double]
    ) -> [String] {
        var failures: [String] = []
        do {
            let currentFanCount = try FanController(smc: smc).fanCount()
            if currentFanCount != fans.count {
                failures.append(
                    "fan count changed from \(fans.count) to \(currentFanCount) during verification"
                )
            }
        } catch {
            failures.append("could not verify fan count: \(error.localizedDescription)")
        }

        for fan in fans {
            do {
                let mode = try requiredNumericValue(smc: smc, key: fan.modeKey, fanIndex: fan.index)
                if mode != 1 {
                    failures.append("fan \(fan.index): mode is \(mode), expected 1")
                }

                guard let targetKey = fan.targetKey,
                      let expectedTarget = expectedTargets[fan.index] else {
                    failures.append("fan \(fan.index): missing target verification state")
                    continue
                }
                let target = try requiredNumericValue(smc: smc, key: targetKey, fanIndex: fan.index)
                if abs(target - expectedTarget) > 1.0 {
                    failures.append(
                        "fan \(fan.index): target is \(target), expected \(expectedTarget)"
                    )
                }
            } catch {
                failures.append("fan \(fan.index): \(error.localizedDescription)")
            }
        }
        return failures
    }
}

private enum LegacyManualHelperInstall {
    private static let launchctlTimeout: TimeInterval = 10
    private static let launchctlTerminationGracePeriod: TimeInterval = 2

    private enum LaunchDaemonState {
        case loaded
        case notLoaded
        case queryFailed(String)
    }

    static var isPresent: Bool {
        let filesArePresent = [
            FanCtlHelperConstants.legacyManualHelperExecutablePath,
            FanCtlHelperConstants.legacyManualHelperPlistPath,
            FanCtlHelperConstants.legacyManualHelperSocketPath,
            FanCtlHelperConstants.legacyManualHelperLogPath
        ].contains(where: pathExistsWithoutFollowingSymlinks)
        if filesArePresent {
            return true
        }
        switch launchDaemonState() {
        case .loaded, .queryFailed:
            return true
        case .notLoaded:
            return false
        }
    }

    static func remove(
        verifyAutomaticAfterBootout: () throws -> Void
    ) throws {
        try validateInstalledFiles()

        switch launchDaemonState() {
        case .loaded:
            let result = runLaunchctl([
                "bootout",
                "system/\(FanCtlHelperConstants.legacyManualHelperIdentifier)"
            ])
            guard result.status == 0 else {
                throw FanCtlHelperError.legacyManualHelperCleanupFailed(
                    result.errorMessage
                )
            }
        case .notLoaded:
            break
        case .queryFailed(let detail):
            throw FanCtlHelperError.legacyManualHelperCleanupFailed(
                "could not determine whether the legacy launch daemon is loaded: \(detail)"
            )
        }

        switch launchDaemonState() {
        case .notLoaded:
            break
        case .loaded:
            throw FanCtlHelperError.legacyManualHelperCleanupFailed(
                "the legacy launch daemon is still loaded"
            )
        case .queryFailed(let detail):
            throw FanCtlHelperError.legacyManualHelperCleanupFailed(
                "could not verify that the legacy launch daemon stopped: \(detail)"
            )
        }

        // A request already accepted by the old helper could race the first
        // verification. Reassert and verify Automatic only after launchd has
        // stopped the old process.
        try verifyAutomaticAfterBootout()

        for path in [
            FanCtlHelperConstants.legacyManualHelperSocketPath,
            FanCtlHelperConstants.legacyManualHelperPlistPath,
            FanCtlHelperConstants.legacyManualHelperExecutablePath,
            FanCtlHelperConstants.legacyManualHelperLogPath
        ] where pathExistsWithoutFollowingSymlinks(path) {
            if unlink(path) != 0, errno != ENOENT {
                throw FanCtlHelperError.legacyManualHelperCleanupFailed(
                    "could not remove \(path): " +
                        String(cString: strerror(errno))
                )
            }
        }

        guard !isPresent else {
            throw FanCtlHelperError.legacyManualHelperCleanupFailed(
                "legacy helper files are still present"
            )
        }
    }

    private static func validateInstalledFiles() throws {
        let executablePath =
            FanCtlHelperConstants.legacyManualHelperExecutablePath
        if pathExistsWithoutFollowingSymlinks(executablePath) {
            guard isRootOwnedRegularFile(executablePath),
                  hasExpectedSignature(executablePath) else {
                throw FanCtlHelperError.invalidLegacyManualHelperInstall(
                    "the installed helper executable has an unexpected identity"
                )
            }
        }

        let plistPath = FanCtlHelperConstants.legacyManualHelperPlistPath
        if pathExistsWithoutFollowingSymlinks(plistPath) {
            guard isRootOwnedRegularFile(plistPath),
                  let data = FileManager.default.contents(atPath: plistPath),
                  let plist = try? PropertyListSerialization.propertyList(
                      from: data,
                      options: [],
                      format: nil
                  ) as? [String: Any],
                  plist["Label"] as? String ==
                    FanCtlHelperConstants.legacyManualHelperIdentifier,
                  let arguments = plist["ProgramArguments"] as? [String],
                  arguments == [executablePath] else {
                throw FanCtlHelperError.invalidLegacyManualHelperInstall(
                    "the installed launch daemon plist is not a known MenuBar FanControl predecessor"
                )
            }
        }
    }

    private static func isRootOwnedRegularFile(_ path: String) -> Bool {
        var information = stat()
        guard lstat(path, &information) == 0 else {
            return false
        }
        return information.st_uid == 0 &&
            (information.st_mode & S_IFMT) == S_IFREG
    }

    private static func pathExistsWithoutFollowingSymlinks(
        _ path: String
    ) -> Bool {
        var information = stat()
        return lstat(path, &information) == 0
    }

    private static func hasExpectedSignature(_ path: String) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(
            URL(fileURLWithPath: path) as CFURL,
            SecCSFlags(),
            &staticCode
        ) == errSecSuccess,
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
        guard SecCodeCopySigningInformation(
            staticCode,
            flags,
            &information
        ) == errSecSuccess,
        let dictionary = information as? [String: Any],
        dictionary[kSecCodeInfoIdentifier as String] as? String ==
            FanCtlHelperConstants.legacyManualHelperIdentifier,
        dictionary[kSecCodeInfoTeamIdentifier as String] as? String ==
            FanCtlHelperConstants.developerTeamIdentifier else {
            return false
        }
        return true
    }

    private static func launchDaemonState() -> LaunchDaemonState {
        let result = runLaunchctl([
            "print",
            "system/\(FanCtlHelperConstants.legacyManualHelperIdentifier)"
        ])
        if result.status == 0 {
            return .loaded
        }
        if result.status == 113 &&
            result.errorMessage.localizedCaseInsensitiveContains(
                "could not find service"
            ) {
            return .notLoaded
        }
        return .queryFailed(result.errorMessage)
    }

    private static func runLaunchctl(
        _ arguments: [String]
    ) -> (status: Int32, errorMessage: String) {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe

        let termination = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            termination.signal()
        }
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }

        guard termination.wait(
            timeout: .now() + launchctlTimeout
        ) == .success else {
            process.terminate()
            _ = termination.wait(
                timeout: .now() + launchctlTerminationGracePeriod
            )
            process.terminationHandler = nil
            return (-1, "launchctl timed out")
        }
        process.terminationHandler = nil

        let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let detail = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (
            process.terminationStatus,
            detail.flatMap { $0.isEmpty ? nil : $0 } ??
                "launchctl exited with status \(process.terminationStatus)"
        )
    }
}

private struct ControllableFan {
    let index: Int
    let modeKey: String
    let targetKey: String?
    let minimumRPM: Double?
    let maximumRPM: Double?

    init(
        index: Int,
        modeKey: String,
        targetKey: String? = nil,
        minimumRPM: Double? = nil,
        maximumRPM: Double? = nil
    ) {
        self.index = index
        self.modeKey = modeKey
        self.targetKey = targetKey
        self.minimumRPM = minimumRPM
        self.maximumRPM = maximumRPM
    }
}

private final class FanCtlHelperDelegate: NSObject, NSXPCListenerDelegate {
    private let service = FanCtlHelperService()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard ConnectionAuthorizer.authorize(connection: connection) else {
            return false
        }

        connection.exportedInterface = NSXPCInterface(with: FanCtlHelperXPCProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

private enum ConnectionAuthorizer {
    static func authorize(connection: NSXPCConnection) -> Bool {
        guard let requirementText = appRequirementTextSignedByCurrentTeam(),
              isAuthorized(pid: connection.processIdentifier, requirementText: requirementText) else {
            return false
        }

        // The PID check above is only an early rejection. This Foundation API binds
        // the requirement to the XPC connection's audit token and revalidates incoming
        // messages, eliminating a PID-reuse time-of-check/time-of-use window.
        connection.setCodeSigningRequirement(requirementText)
        return true
    }

    private static func isAuthorized(pid: pid_t, requirementText: String) -> Bool {
        guard pid > 0 else {
            return false
        }

        var code: SecCode?
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, SecCSFlags(), &code) == errSecSuccess,
              let code else {
            return false
        }

        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementText as CFString, SecCSFlags(), &requirement) == errSecSuccess,
              let requirement else {
            return false
        }

        return SecCodeCheckValidity(code, SecCSFlags(), requirement) == errSecSuccess
    }

    private static func appRequirementTextSignedByCurrentTeam() -> String? {
        guard let teamIdentifier = currentCodeTeamIdentifier(),
              !teamIdentifier.isEmpty,
              teamIdentifier.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains) else {
            return nil
        }

        return """
        identifier "\(FanCtlHelperConstants.appBundleIdentifier)" and anchor apple generic and certificate leaf[subject.OU] = "\(teamIdentifier)"
        """
    }

    private static func currentCodeTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess,
              let code else {
            return nil
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode else {
            return nil
        }

        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
              let dictionary = information as? [String: Any],
              let teamIdentifier = dictionary[kSecCodeInfoTeamIdentifier as String] as? String,
              !teamIdentifier.isEmpty else {
            return nil
        }

        return teamIdentifier
    }
}

private enum FanCtlHelperError: LocalizedError {
    case invalidMutationSequence(String)
    case staleMutationSequence(received: Int64, latest: Int64)
    case invalidRPM(String)
    case rpmOutsideFanRange(requested: Double, fanIndex: Int, minimum: Double, maximum: Double)
    case manualLeaseInactive
    case invalidFanCount(String)
    case missingFanMode(fanIndex: Int, failures: [String])
    case requiredKeyUnavailable(key: String, fanIndex: Int?, detail: String)
    case invalidFanConfiguration(fanIndex: Int, detail: String)
    case fanOperationFailed(operation: String, fanIndex: Int, detail: String)
    case incompleteOperation(operation: String, failures: [String])
    case automaticRecoveryFailed(primary: String, failures: [String])
    case invalidLegacyManualHelperInstall(String)
    case legacyManualHelperCleanupFailed(String)

    var wireCode: String {
        switch self {
        case .invalidMutationSequence:
            "invalid_request"
        case .staleMutationSequence:
            "stale_request"
        case .invalidRPM, .rpmOutsideFanRange:
            "invalid_rpm"
        case .manualLeaseInactive:
            "manual_lease_inactive"
        case .invalidFanCount, .missingFanMode, .requiredKeyUnavailable:
            "fan_enumeration_failed"
        case .invalidFanConfiguration:
            "invalid_fan_configuration"
        case .fanOperationFailed, .incompleteOperation:
            "fan_control_failed"
        case .automaticRecoveryFailed:
            "automatic_recovery_failed"
        case .invalidLegacyManualHelperInstall,
             .legacyManualHelperCleanupFailed:
            "legacy_cleanup_failed"
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidMutationSequence(let value):
            "The fan command sequence is invalid: \(value)."
        case .staleMutationSequence(let received, let latest):
            "Ignored stale fan command sequence \(received); latest is \(latest)."
        case .invalidRPM(let value):
            "RPM must be a whole number between \(FanCtlHelperConstants.minimumRPM) and \(FanCtlHelperConstants.maximumEncodedRPM); received \(value)."
        case .rpmOutsideFanRange(let requested, let fanIndex, let minimum, let maximum):
            "Requested RPM \(requested) is outside fan \(fanIndex)'s supported range \(minimum)...\(maximum)."
        case .manualLeaseInactive:
            "The manual-control safety lease is not active; reapply the selected fan mode before renewing it."
        case .invalidFanCount(let value):
            "FNum did not describe a complete, non-empty fan set: \(value)."
        case .missingFanMode(let fanIndex, let failures):
            "Fan \(fanIndex) has no readable mode key (\(failures.joined(separator: "; ")))."
        case .requiredKeyUnavailable(let key, let fanIndex, let detail):
            if let fanIndex {
                "Required key \(key) for fan \(fanIndex) is unavailable: \(detail)"
            } else {
                "Required key \(key) is unavailable: \(detail)"
            }
        case .invalidFanConfiguration(let fanIndex, let detail):
            "Fan \(fanIndex) reported an unsafe configuration: \(detail)."
        case .fanOperationFailed(let operation, let fanIndex, let detail):
            "Could not \(operation) for fan \(fanIndex): \(detail)"
        case .incompleteOperation(let operation, let failures):
            "Could not complete \(operation) for every fan: \(failures.joined(separator: "; "))."
        case .automaticRecoveryFailed(let primary, let failures):
            "\(primary) Automatic recovery also failed: \(failures.joined(separator: "; "))."
        case .invalidLegacyManualHelperInstall(let detail):
            "The previous helper installation could not be verified: \(detail)."
        case .legacyManualHelperCleanupFailed(let detail):
            "The previous helper installation could not be removed: \(detail)."
        }
    }
}

private func wireFailure(for error: Error) -> FanCtlHelperWireFailure {
    if let helperError = error as? FanCtlHelperError {
        return FanCtlHelperWireFailure(
            code: helperError.wireCode,
            message: helperError.localizedDescription
        )
    }

    if let smcError = error as? SMCError {
        let code: String
        switch smcError {
        case .serviceNotFound, .openFailed:
            code = "smc_unavailable"
        case .readFailed, .invalidKey, .invalidDataSize, .invalidDataType, .invalidNumericValue:
            code = "smc_read_failed"
        case .writeFailed, .firmwareRejected:
            code = "smc_write_failed"
        }
        return FanCtlHelperWireFailure(code: code, message: smcError.localizedDescription)
    }

    return FanCtlHelperWireFailure(code: "internal_error", message: error.localizedDescription)
}

private let delegate = FanCtlHelperDelegate()
private let listener = NSXPCListener(machServiceName: FanCtlHelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
