import AppKit

enum StartupGuard {
    static func shouldLaunch() -> Bool {
        let peers = NSRunningApplication.runningApplications(withBundleIdentifier: "dev.nikoko.SeasonArt")
            .map { (pid: $0.processIdentifier, finishedLaunching: $0.isFinishedLaunching) }
        return shouldLaunch(currentPID: ProcessInfo.processInfo.processIdentifier, peers: peers)
    }

    static func shouldLaunch(currentPID: Int32, peers: [(pid: Int32, finishedLaunching: Bool)]) -> Bool {
        !peers.contains { peer in
            peer.pid != currentPID && (peer.finishedLaunching || peer.pid < currentPID)
        }
    }
}
