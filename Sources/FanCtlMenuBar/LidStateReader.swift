import Foundation
import IOKit

enum LidStateReader {
    static func isLidClosed() -> Bool? {
        guard let matching = IOServiceMatching("IOPMrootDomain") else {
            return nil
        }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else {
            return nil
        }
        defer { IOObjectRelease(service) }

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
