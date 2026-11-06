import AppKit
import Foundation

// Завершаем только приложения с собственной точной bundle identity.
let applications = NSRunningApplication.runningApplications(withBundleIdentifier: "dev.nikoko.SeasonArt")
for application in applications {
    application.terminate()
}
let deadline = Date().addingTimeInterval(5)
while applications.contains(where: { !$0.isTerminated }) && Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}
if applications.contains(where: { !$0.isTerminated }) ||
    !NSRunningApplication.runningApplications(withBundleIdentifier: "dev.nikoko.SeasonArt").isEmpty {
    fputs("SeasonArt did not terminate within five seconds; installation aborted.\n", stderr)
    exit(1)
}
