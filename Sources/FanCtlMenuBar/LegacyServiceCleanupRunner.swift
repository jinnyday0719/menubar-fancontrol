import FanCtlHelperXPC
import Darwin
import Foundation
import Security

enum FanCtlLegacyServiceCleanupRunner {
    private static let executionTimeout: TimeInterval = 180
    private static let terminationGracePeriod: TimeInterval = 2
    private static let forcedTerminationGracePeriod: TimeInterval = 2

    static func inspect() async throws -> FanCtlLegacyCleanupReport {
        try await execute(arguments: ["--report-only"])
    }

    static func run(
        automaticAlreadyRestored: Bool = false
    ) async throws -> FanCtlLegacyCleanupReport {
        try await execute(
            arguments: automaticAlreadyRestored
                ? ["--automatic-already-restored"]
                : []
        )
    }

    private static func execute(
        arguments: [String]
    ) async throws -> FanCtlLegacyCleanupReport {
        let cleanupAppURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/Helpers", isDirectory: true)
            .appendingPathComponent(
                "\(FanCtlHelperConstants.legacyCleanupAppName).app",
                isDirectory: true
            )
        let executableURL = cleanupAppURL
            .appendingPathComponent("Contents/MacOS", isDirectory: true)
            .appendingPathComponent(
                FanCtlHelperConstants.legacyCleanupExecutableName
            )

        guard FileManager.default.isExecutableFile(atPath: executableURL.path),
              isTrustedCleanupApplication(cleanupAppURL) else {
            throw LegacyCleanupRunnerError.invalidCleanupApplication
        }

        return try await Task.detached {
            try runCleanupProcess(
                executableURL: executableURL,
                arguments: arguments
            )
        }.value
    }

    private static func runCleanupProcess(
        executableURL: URL,
        arguments: [String]
    ) throws -> FanCtlLegacyCleanupReport {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError
        let termination = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            termination.signal()
        }

        do {
            try process.run()
        } catch {
            throw LegacyCleanupRunnerError.couldNotLaunch(
                error.localizedDescription
            )
        }
        guard termination.wait(
            timeout: .now() + executionTimeout
        ) == .success else {
            process.terminate()
            if termination.wait(
                timeout: .now() + terminationGracePeriod
            ) != .success {
                let processIdentifier = process.processIdentifier
                let killResult = process.isRunning
                    ? Darwin.kill(processIdentifier, SIGKILL)
                    : 0
                let killError = errno
                let didExit =
                    termination.wait(
                        timeout: .now() + forcedTerminationGracePeriod
                    ) == .success || !process.isRunning
                guard (killResult == 0 || killError == ESRCH), didExit else {
                    process.terminationHandler = nil
                    throw LegacyCleanupRunnerError.cleanupCouldNotBeTerminated
                }
            }
            process.terminationHandler = nil
            throw LegacyCleanupRunnerError.cleanupTimedOut
        }
        process.terminationHandler = nil

        guard process.terminationReason == .exit,
              process.terminationStatus == 0 else {
            let data = standardError.fileHandleForReading.readDataToEndOfFile()
            let detail = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw LegacyCleanupRunnerError.cleanupFailed(
                detail.flatMap { $0.isEmpty ? nil : $0 } ??
                    "The migration bridge exited with status " +
                    "\(process.terminationStatus)."
            )
        }

        let outputData =
            standardOutput.fileHandleForReading.readDataToEndOfFile()
        do {
            return try JSONDecoder().decode(
                FanCtlLegacyCleanupReport.self,
                from: outputData
            )
        } catch {
            throw LegacyCleanupRunnerError.invalidCleanupReport
        }
    }

    private static func isTrustedCleanupApplication(_ bundleURL: URL) -> Bool {
        guard Bundle(url: bundleURL)?.bundleIdentifier ==
                FanCtlHelperConstants.legacyAppBundleIdentifier else {
            return false
        }

        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(
            bundleURL as CFURL,
            SecCSFlags(),
            &staticCode
        ) == errSecSuccess,
        let staticCode,
        SecStaticCodeCheckValidity(staticCode, SecCSFlags(), nil) == errSecSuccess else {
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
            FanCtlHelperConstants.legacyAppBundleIdentifier,
        dictionary[kSecCodeInfoTeamIdentifier as String] as? String ==
            FanCtlHelperConstants.developerTeamIdentifier else {
            return false
        }
        return true
    }
}

enum LegacyCleanupRunnerError: LocalizedError {
    case invalidCleanupApplication
    case couldNotLaunch(String)
    case cleanupFailed(String)
    case invalidCleanupReport
    case cleanupTimedOut
    case cleanupCouldNotBeTerminated

    var errorDescription: String? {
        switch self {
        case .invalidCleanupApplication:
            "The signed legacy cleanup component is missing or invalid."
        case .couldNotLaunch(let detail):
            "Could not launch the legacy cleanup component: \(detail)"
        case .cleanupFailed(let detail):
            detail
        case .invalidCleanupReport:
            "The signed legacy cleanup component returned an invalid result."
        case .cleanupTimedOut:
            "The signed legacy cleanup component did not finish in time."
        case .cleanupCouldNotBeTerminated:
            "The timed-out legacy cleanup component could not be terminated safely."
        }
    }
}
