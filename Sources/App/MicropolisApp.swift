// MicropolisApp.swift — app entry point (macOS + iPadOS).
// Part of a modified version of Micropolis (GPL-3.0).

import SwiftUI

#if os(macOS)
/// AppKit refuses to quit while a window has a sheet attached (and the start
/// sheet cannot be dismissed while there is no city), so ⌘Q did nothing.
/// Quitting therefore closes any open sheets first, then terminates. The city
/// is autosaved on willTerminate.
@MainActor
func quitApp() {
    // Ask the UI to dismiss every sheet, then quit once they are gone.
    NotificationCenter.default.post(name: .micropolisCommand, object: "dismissSheets")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
        NSApplication.shared.terminate(nil)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Quit requests from the Dock, logout or shutdown arrive as an Apple
        // event; route them through quitApp() so an open sheet cannot block them.
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleQuit(_:withReply:)),
            forEventClass: AEEventClass(kCoreEventClass), andEventID: AEEventID(kAEQuitApplication))
    }

    @objc func handleQuit(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        MainActor.assumeIsolated { quitApp() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
#endif

@main
struct MicropolisApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @State private var model = GameModel()

    var body: some Scene {
        #if os(macOS)
        Window("Micropolis", id: "main") {
            NavigationStack { ContentView(model: model) }
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands { commands }
        #else
        WindowGroup {
            NavigationStack { ContentView(model: model) }
        }
        .commands { commands }
        #endif
    }

    @CommandsBuilder
    private var commands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L("New City…", "新しい都市…")) { send("new") }
                .keyboardShortcut("n")
            Button(L("Open City…", "都市を開く…")) { send("open") }
                .keyboardShortcut("o")
        }
        CommandGroup(replacing: .saveItem) {
            Button(L("Save City…", "都市を保存…")) { send("save") }
                .keyboardShortcut("s")
        }
        CommandGroup(replacing: .appInfo) {
            Button(L("About Micropolis", "Micropolis について")) { send("about") }
        }
        #if os(macOS)
        CommandGroup(replacing: .appTermination) {
            Button(L("Quit Micropolis", "Micropolis を終了")) { quitApp() }
                .keyboardShortcut("q")
        }
        #endif
        CommandMenu(L("Simulation", "シミュレーション")) {
            ForEach(SimSpeed.allCases) { s in
                Button(s.title) { model.speed = s }
                    .keyboardShortcut(KeyEquivalent(Character("\(s.rawValue)")), modifiers: .command)
            }
            Divider()
            Button(L("Budget…", "予算…")) { send("budget") }
                .keyboardShortcut("b")
            Button(L("Evaluation…", "評価…")) { send("evaluation") }
                .keyboardShortcut("e")
        }
        CommandMenu(L("Map", "マップ")) {
            Picker(L("Map Overlay", "マップ表示"), selection: $model.overlay) {
                ForEach(OverlayInfo.all) { o in Text(o.name).tag(o.overlay) }
            }
            .pickerStyle(.inline)
            Divider()
            Menu(L("Disasters", "災害")) {
                DisasterButtons(model: model)
            }
        }
    }

    private func send(_ cmd: String) {
        NotificationCenter.default.post(name: .micropolisCommand, object: cmd)
    }
}
