//
//  SystemMonitorApp.swift
//  syswatch
//
//  Created by Gerrit Grunwald on 30.09.26.
//

import Foundation
import SwiftUI
import AppKit


@main
struct SystemMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject                                    private var monitor = MetricsMonitor.shared

    
    var body: some Scene {
        MenuBarExtra {
            MenuBarView(monitor: monitor)
        } label: {
            Image(systemName: "gauge.with.dots.needle.67percent")
        }
        .menuBarExtraStyle(.window)
    }
}


// Starts sampling at launch. Content inside MenuBarExtra is only built when the
// window is opened, so starting the monitor from the view would be too late.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let server  : MetricsWebSocketServer = MetricsWebSocketServer(port: 8787)
    private let encoder : JSONEncoder            = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only, no Dock icon. Setting LSUIElement = YES in Info.plist does the same thing without the brief Dock flash at launch.
        NSApp.setActivationPolicy(.accessory)

        // Encode on the main actor (where the snapshot type lives), send from the server's queue.
        MetricsMonitor.shared.onSnapshot = { [weak self] snapshot in
            guard let self else { return }
            let message = WireSnapshot(snapshot: snapshot, config: MetricsMonitor.shared.config)
            if let json = try? encoder.encode(message) {
                server.broadcast(json)
            }
        }

        server.start()
        MetricsMonitor.shared.start()
    }
}
