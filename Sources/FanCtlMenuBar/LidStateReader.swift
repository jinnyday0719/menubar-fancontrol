import Dispatch
import Foundation
import IOKit

enum LidStateReader {
    private static let rootDomain = RootDomainHandle()
    static let isSupported = rootDomain.readLidState() != nil

    static func isLidClosed() -> Bool? {
        rootDomain.readLidState()
    }

    static func observeChanges(
        _ handler: @escaping @Sendable (LidStateEvent) -> Void
    ) -> LidStateObservation? {
        LidStateObservation.make(handler: handler)
    }
}

enum LidStateEvent: Sendable {
    case stateChanged(isClosed: Bool)
    case serviceTerminated
}

private final class RootDomainHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var service: io_service_t = 0

    deinit {
        if service != 0 {
            IOObjectRelease(service)
        }
    }

    func readLidState() -> Bool? {
        lock.lock()
        defer { lock.unlock() }

        if service == 0 {
            service = Self.openService()
        }
        guard service != 0 else {
            return nil
        }

        if let state = Self.readLidState(from: service) {
            return state
        }

        // The root-domain handle can become stale across sleep or a power
        // management service restart. Reacquire it once before giving up.
        IOObjectRelease(service)
        service = Self.openService()
        guard service != 0 else {
            return nil
        }
        return Self.readLidState(from: service)
    }

    private static func openService() -> io_service_t {
        guard let matching = IOServiceMatching("IOPMrootDomain") else {
            return 0
        }
        return IOServiceGetMatchingService(kIOMainPortDefault, matching)
    }

    private static func readLidState(from service: io_service_t) -> Bool? {
        guard let value = IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            return nil
        }

        return (value as? NSNumber)?.boolValue
    }
}

final class LidStateObservation: @unchecked Sendable {
    // IOPM.h declares this macro as
    // iokit_family_msg(sub_iokit_powermanagement, 0x100). Clang cannot import
    // that macro into Swift, so retain the SDK-defined UInt32 value here.
    private static let clamshellStateChangeMessage: UInt32 = 0xe003_4100
    // IOMessage.h declares iokit_common_msg(0x010), which Clang also cannot
    // import into Swift.
    private static let serviceTerminatedMessage: UInt32 = 0xe000_0010
    private static let clamshellStateBit: UInt = 1 << 0

    private let handler: @Sendable (LidStateEvent) -> Void
    private var notificationPort: IONotificationPortRef?
    private var notification: io_object_t = 0

    private init(handler: @escaping @Sendable (LidStateEvent) -> Void) {
        self.handler = handler
    }

    static func make(
        handler: @escaping @Sendable (LidStateEvent) -> Void
    ) -> LidStateObservation? {
        let observation = LidStateObservation(handler: handler)
        return observation.start() ? observation : nil
    }

    deinit {
        invalidate()
    }

    func invalidate() {
        if notification != 0 {
            IOObjectRelease(notification)
            notification = 0
        }
        if let notificationPort {
            IONotificationPortSetDispatchQueue(notificationPort, nil)
            IONotificationPortDestroy(notificationPort)
            self.notificationPort = nil
        }
    }

    private func start() -> Bool {
        guard let matching = IOServiceMatching("IOPMrootDomain") else {
            return false
        }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else {
            return false
        }
        defer { IOObjectRelease(service) }

        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            return false
        }
        notificationPort = port
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)

        let result = IOServiceAddInterestNotification(
            port,
            service,
            kIOGeneralInterest,
            Self.interestCallback,
            Unmanaged.passUnretained(self).toOpaque(),
            &notification
        )
        guard result == KERN_SUCCESS else {
            invalidate()
            return false
        }
        return true
    }

    private static let interestCallback: IOServiceInterestCallback = {
        refCon,
        _,
        messageType,
        messageArgument
        in
        guard let refCon else {
            return
        }

        let observation = Unmanaged<LidStateObservation>
            .fromOpaque(refCon)
            .takeUnretainedValue()
        switch messageType {
        case clamshellStateChangeMessage:
            let bits = UInt(bitPattern: messageArgument)
            observation.handler(.stateChanged(
                isClosed: bits & clamshellStateBit != 0
            ))
        case serviceTerminatedMessage:
            observation.handler(.serviceTerminated)
        default:
            break
        }
    }
}
