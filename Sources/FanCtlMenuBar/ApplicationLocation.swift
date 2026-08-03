import Foundation

enum FanCtlApplicationLocation {
    static func isInstalledApplication(
        _ bundleURL: URL = Bundle.main.bundleURL
    ) -> Bool {
        let resolvedBundleURL = bundleURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let parentURL = resolvedBundleURL
            .deletingLastPathComponent()
            .standardizedFileURL
        if parentURL.path == "/Applications" ||
            parentURL.path.hasPrefix("/Applications/") {
            return true
        }

        let userApplicationsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .standardizedFileURL
        return parentURL == userApplicationsURL ||
            parentURL.path.hasPrefix(userApplicationsURL.path + "/")
    }
}
