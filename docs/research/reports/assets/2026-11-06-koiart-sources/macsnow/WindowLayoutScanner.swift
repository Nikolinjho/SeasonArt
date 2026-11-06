import AppKit
import CoreGraphics
import Foundation

struct WindowSnapshot: Equatable {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let bounds: CGRect
    let order: Int
}

@MainActor
final class WindowLayoutScanner {
    var onSnapshot: (([WindowSnapshot]) -> Void)?

    private var timer: Timer?
    private let minimumWindowSize: CGFloat = 100

    func start() {
        stop()
        timer = Timer.scheduledTimer(
            withTimeInterval: 0.5,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scan()
            }
        }
        scan()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func scan() {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let rawWindows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            onSnapshot?([])
            return
        }

        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let snapshots = rawWindows.enumerated().compactMap { order, info -> WindowSnapshot? in
            guard
                let windowNumber = info[kCGWindowNumber as String] as? UInt32,
                let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                let ownerName = info[kCGWindowOwnerName as String] as? String,
                ownerPID != currentPID,
                ownerName != appName,
                (info[kCGWindowLayer as String] as? Int) == 0,
                let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                bounds.width >= minimumWindowSize,
                bounds.height >= minimumWindowSize
            else {
                return nil
            }

            return WindowSnapshot(windowID: CGWindowID(windowNumber), ownerPID: ownerPID, ownerName: ownerName, bounds: bounds, order: order)
        }

        onSnapshot?(Array(snapshots.prefix(20)))
    }
}
