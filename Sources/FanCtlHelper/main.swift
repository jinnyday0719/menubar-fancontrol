import FanCtlCore
import FanCtlHelperXPC
import Foundation
import Security

private final class FanCtlHelperService: NSObject, FanCtlHelperXPCProtocol {
    func ping(withReply reply: @escaping (NSString?, NSString?) -> Void) {
        reply("pong", nil)
    }

    func setAutomatic(withReply reply: @escaping (NSString?, NSString?) -> Void) {
        complete(reply) {
            try setAutomatic()
            return "automatic"
        }
    }

    func setMaximum(withReply reply: @escaping (NSString?, NSString?) -> Void) {
        complete(reply) {
            try setMaximum()
            return "maximum"
        }
    }

    func setRPM(_ rpm: NSNumber, withReply reply: @escaping (NSString?, NSString?) -> Void) {
        complete(reply) {
            let value = rpm.doubleValue
            guard value.isFinite, value >= 0 else {
                throw FanCtlHelperError.invalidRPM(rpm.stringValue)
            }
            try setRPM(value)
            return "rpm \(Int(value.rounded()))"
        }
    }

    private func complete(
        _ reply: @escaping (NSString?, NSString?) -> Void,
        operation: () throws -> String
    ) {
        do {
            reply(try operation() as NSString, nil)
        } catch {
            reply(nil, error.localizedDescription as NSString)
        }
    }

    private func setAutomatic() throws {
        let smc = try SMCConnection()
        let reader = SensorReader(smc: smc)
        let controller = FanController(smc: smc)

        for fan in reader.snapshot().fans {
            try controller.setAutomatic(fanIndex: fan.index)
        }
    }

    private func setMaximum() throws {
        let smc = try SMCConnection()
        let reader = SensorReader(smc: smc)
        let controller = FanController(smc: smc)

        for fan in reader.snapshot().fans {
            guard let maximumRPM = fan.maximumRPM else {
                continue
            }
            _ = try controller.setManual(fanIndex: fan.index, rpm: maximumRPM)
        }
    }

    private func setRPM(_ rpm: Double) throws {
        let smc = try SMCConnection()
        let reader = SensorReader(smc: smc)
        let controller = FanController(smc: smc)

        for fan in reader.snapshot().fans {
            _ = try controller.setManual(fanIndex: fan.index, rpm: rpm)
        }
    }
}

private final class FanCtlHelperDelegate: NSObject, NSXPCListenerDelegate {
    private let service = FanCtlHelperService()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard ConnectionAuthorizer.isAuthorized(pid: connection.processIdentifier) else {
            return false
        }

        connection.exportedInterface = NSXPCInterface(with: FanCtlHelperXPCProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

private enum ConnectionAuthorizer {
    static func isAuthorized(pid: pid_t) -> Bool {
        guard let requirementText = appRequirementTextSignedByCurrentTeam() else {
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
        guard let teamIdentifier = currentCodeTeamIdentifier() else {
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
    case invalidRPM(String)

    var errorDescription: String? {
        switch self {
        case .invalidRPM(let value):
            "invalid RPM: \(value)"
        }
    }
}

private let delegate = FanCtlHelperDelegate()
private let listener = NSXPCListener(machServiceName: FanCtlHelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
