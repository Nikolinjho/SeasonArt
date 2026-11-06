import AppKit
import Darwin

let app = NSApplication.shared
guard StartupGuard.shouldLaunch() else { exit(EXIT_SUCCESS) }
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
