// GameModel.swift — drives the Micropolis engine and publishes state to SwiftUI.
// Part of a modified version of Micropolis (GPL-3.0).

import SwiftUI
import Observation
import AVFoundation
#if os(iOS)
import UIKit
#endif

enum SimSpeed: Int, CaseIterable, Identifiable {
    case paused, slow, normal, fast, ultra
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .paused: return L("Pause", "一時停止")
        case .slow: return L("Slow", "遅い")
        case .normal: return L("Normal", "普通")
        case .fast: return L("Fast", "速い")
        case .ultra: return L("Ultra", "超高速")
        }
    }

    var symbol: String {
        switch self {
        case .paused: return "pause.fill"
        case .slow: return "tortoise.fill"
        case .normal: return "play.fill"
        case .fast: return "forward.fill"
        case .ultra: return "hare.fill"
        }
    }

    /// Simulation ticks per 30 Hz frame (fractional = every Nth frame).
    var ticksPerFrame: Double {
        switch self {
        case .paused: return 0
        case .slow: return 1.0 / 3.0
        case .normal: return 1
        case .fast: return 2
        case .ultra: return 2
        }
    }

    var passes: Int { self == .ultra ? 5 : 1 }
}

struct GameMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let important: Bool
    let x: Int
    let y: Int
    var hasLocation: Bool { x >= 0 && y >= 0 && x < MPWorldWidth && y < MPWorldHeight }
}

struct ZoneStatus: Identifiable {
    let id = UUID()
    let category: String
    let population: String
    let landValue: String
    let crime: String
    let pollution: String
    let growth: String
    let x: Int
    let y: Int
}

/// One user edit (a tap or a whole drag): the cells it changed and what it cost.
struct MapEdit {
    let indices: Data   // Int32 cell indices (x * WORLD_H + y)
    let before: Data    // UInt16 values before the edit
    let after: Data     // UInt16 values after the edit
    let cost: Int
    let actionName: String
}

struct FocusRequest: Equatable {
    let id = UUID()
    let x: Int
    let y: Int
}

enum GameAlert: Identifiable {
    case won, lost, toolError(String)
    var id: String {
        switch self {
        case .won: return "won"
        case .lost: return "lost"
        case .toolError(let s): return "err" + s
        }
    }
}

@MainActor
@Observable
final class GameModel: NSObject {

    let engine: MPEngine

    // Rendering. The map image is pushed straight to the map layer (not observed)
    // so SwiftUI does not re-evaluate views 30 times a second.
    @ObservationIgnored var mapImage: CGImage?
    @ObservationIgnored var frameSink: ((CGImage?) -> Void)?
    var miniMapImage: CGImage?
    var overlay: MPOverlay = .none { didSet { needsRender = true } }

    // State mirrored from the engine
    var cityName = ""
    var funds = 0
    var dateText = ""
    var population = 0
    var cityClass = 0
    var demandR = 0
    var demandC = 0
    var demandI = 0
    var taxRate = 7

    // UI
    var tool: MPTool = .query
    var speed: SimSpeed = .normal { didSet { applySpeed() } }
    var messages: [GameMessage] = []
    var latestMessage: GameMessage?
    var zoneStatus: ZoneStatus?
    var focusRequest: FocusRequest?
    var alert: GameAlert?
    var showBudget = false
    var showEvaluation = false
    var showNewCity = false
    var showAbout = false
    var soundEnabled = true {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled") }
    }
    var hasCity = false
    /// Bumped whenever the undo stack changes, so SwiftUI refreshes undo buttons.
    var undoRevision = 0
    /// The window's undo manager (set by ContentView).
    @ObservationIgnored weak var undoManager: UndoManager?

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var tickAccumulator = 0.0
    @ObservationIgnored private var needsRender = true
    @ObservationIgnored private var frameCount = 0
    @ObservationIgnored private var players: [String: AVAudioPlayer] = [:]
    @ObservationIgnored private var lastSoundTime: [String: Date] = [:]
    @ObservationIgnored private var speedBeforeModal: SimSpeed?

    override init() {
        let resources = Bundle.main.resourcePath ?? ""
        engine = MPEngine(resourcePath: resources)
        super.init()
        if UserDefaults.standard.object(forKey: "soundEnabled") != nil {
            soundEnabled = UserDefaults.standard.bool(forKey: "soundEnabled")
        }
        engine.delegate = self
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        #endif
        startTimer()
        // Save the city when the app quits (⌘Q) or goes to the background.
        #if os(macOS)
        let quitNote = NSApplication.willTerminateNotification
        #else
        let quitNote = UIApplication.didEnterBackgroundNotification
        #endif
        NotificationCenter.default.addObserver(forName: quitNote, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.autosave() }
        }
    }

    // MARK: Loop

    private func startTimer() {
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.frame() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func applySpeed() {
        engine.paused = (speed == .paused)
        engine.setPasses(speed.passes)
        tickAccumulator = 0
    }

    private func frame() {
        guard hasCity else { return }
        frameCount += 1
        if speed != .paused && strokeBefore == nil {
            tickAccumulator += speed.ticksPerFrame
            while tickAccumulator >= 1 {
                engine.tick()
                tickAccumulator -= 1
                needsRender = true
            }
        } else if frameCount % 8 == 0 {
            needsRender = true // keep the "no power" blink alive while paused
        }
        if needsRender {
            render()
        }
        if frameCount % 6 == 0 {
            refreshState()
        }
        if frameCount % autosaveIntervalFrames == 0 {
            autosave()
        }
    }

    func render() {
        needsRender = false
        mapImage = engine.renderImage(with: overlay)
        frameSink?(mapImage)
        if frameCount % 15 == 0 || miniMapImage == nil {
            miniMapImage = engine.renderMiniMap()
        }
    }

    func refreshState() {
        let name = engine.cityName
        if name != cityName { cityName = name }
        if engine.funds != funds { funds = engine.funds }
        let d = GameText.date(year: engine.year, month: engine.month)
        if d != dateText { dateText = d }
        if engine.population != population { population = engine.population }
        if engine.cityClass != cityClass { cityClass = engine.cityClass }
        if engine.residentialDemand != demandR { demandR = engine.residentialDemand }
        if engine.commercialDemand != demandC { demandC = engine.commercialDemand }
        if engine.industrialDemand != demandI { demandI = engine.industrialDemand }
        if engine.taxRate != taxRate { taxRate = engine.taxRate }
    }

    private func cityLoaded() {
        hasCity = true
        undoManager?.removeAllActions()
        strokeBefore = nil
        undoRevision += 1
        messages.removeAll()
        latestMessage = nil
        zoneStatus = nil
        applySpeed()
        needsRender = true
        miniMapImage = nil
        render()
        refreshState()
        focusRequest = FocusRequest(x: Int(MPWorldWidth) / 2, y: Int(MPWorldHeight) / 2)
    }

    // MARK: Cities

    func newRandomCity(level: Int) {
        engine.gameLevel = level
        engine.generateRandomCity()
        cityLoaded()
    }

    func loadScenario(_ n: Int) {
        engine.loadScenario(n)
        cityLoaded()
    }

    func loadSampleCity(_ name: String) {
        guard let path = Bundle.main.path(forResource: name, ofType: "cty", inDirectory: "cities") else { return }
        if engine.loadCity(atPath: path) { cityLoaded() }
    }

    func loadCity(url: URL) -> Bool {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        // Copy into a temporary location so the engine can fopen() it.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("open-\(UUID().uuidString).cty")
        defer { try? FileManager.default.removeItem(at: tmp) }
        do { try FileManager.default.copyItem(at: url, to: tmp) } catch { return false }
        let ok = engine.loadCity(atPath: tmp.path)
        if ok {
            cityLoaded()
            engine.cityName = url.deletingPathExtension().lastPathComponent
            refreshState()
        }
        return ok
    }

    // MARK: Autosave

    /// About once a minute (the loop runs at 30 Hz).
    private let autosaveIntervalFrames = 30 * 60

    private struct AutosaveInfo: Codable {
        let cityName: String
        let savedAt: Date
    }

    private var autosaveDirectory: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let id = Bundle.main.bundleIdentifier ?? "com.coastandcorp.app.micropolis"
        return base.appendingPathComponent(id, isDirectory: true).appendingPathComponent("Autosave", isDirectory: true)
    }

    /// Saves the current city to the app's own storage, so quitting never loses it.
    func autosave() {
        guard hasCity, let dir = autosaveDirectory, let data = cityData() else { return }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: dir.appendingPathComponent("city.cty"), options: .atomic)
            let info = AutosaveInfo(cityName: engine.cityName, savedAt: Date())
            try JSONEncoder().encode(info).write(to: dir.appendingPathComponent("info.json"), options: .atomic)
        } catch {
            // Autosave is best effort; the player can still save manually.
        }
    }

    /// Reopens the autosaved city. Returns false if there is none (or it is unreadable).
    @discardableResult
    func restoreAutosave() -> Bool {
        guard let dir = autosaveDirectory else { return false }
        let file = dir.appendingPathComponent("city.cty")
        guard FileManager.default.fileExists(atPath: file.path), engine.loadCity(atPath: file.path) else {
            return false
        }
        cityLoaded()
        if let data = try? Data(contentsOf: dir.appendingPathComponent("info.json")),
           let info = try? JSONDecoder().decode(AutosaveInfo.self, from: data), !info.cityName.isEmpty {
            engine.cityName = info.cityName
        }
        refreshState()
        let m = GameMessage(text: L("Resumed where you left off.", "前回の続きから再開しました。"),
                            important: false, x: -1, y: -1)
        latestMessage = m
        messages.insert(m, at: 0)
        return true
    }

    /// Serialises the current city to .cty data.
    func cityData() -> Data? {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("save-\(UUID().uuidString).cty")
        defer { try? FileManager.default.removeItem(at: tmp) }
        guard engine.saveCity(toPath: tmp.path) else { return nil }
        return try? Data(contentsOf: tmp)
    }

    // MARK: Tools

    private var lastToolTile: (Int, Int)?
    /// Map and funds captured when the current stroke began (nil = no stroke).
    @ObservationIgnored private var strokeBefore: Data?
    @ObservationIgnored private var strokeFunds = 0

    private var toolEditsMap: Bool { tool != .query }

    /// Called when a drag/tap starts on a tile.
    func toolBegan(x: Int, y: Int) {
        lastToolTile = nil
        if toolEditsMap {
            // The simulation is held while a stroke is in progress so the
            // before/after diff only contains the player's own changes.
            strokeBefore = engine.mapSnapshot()
            strokeFunds = engine.funds
        }
        if MPEngine.size(of: tool) == 1 && toolEditsMap {
            applyTool(x: x, y: y)
        }
    }

    /// Called while dragging: line tools paint along the path.
    func toolMoved(x: Int, y: Int) {
        guard MPEngine.size(of: tool) == 1, toolEditsMap else { return }
        guard let (lx, ly) = lastToolTile else { applyTool(x: x, y: y); return }
        if lx == x && ly == y { return }
        // Walk one axis at a time (no diagonal steps) so roads stay connected.
        var x0 = lx, y0 = ly
        let totalX = abs(x - lx), totalY = abs(y - ly)
        while !(x0 == x && y0 == y) {
            let remX = abs(x - x0), remY = abs(y - y0)
            // Step along the axis that is proportionally further from the goal.
            if remX > 0 && (remY == 0 || remX * max(totalY, 1) >= remY * max(totalX, 1)) {
                x0 += x0 < x ? 1 : -1
            } else {
                y0 += y0 < y ? 1 : -1
            }
            applyTool(x: x0, y: y0)
        }
    }

    /// Called when a drag/tap ends.
    func toolEnded(x: Int, y: Int) {
        if MPEngine.size(of: tool) > 1 || tool == .query {
            applyTool(x: x, y: y)
        }
        lastToolTile = nil
        commitStroke()
    }

    /// Called when the gesture is cancelled: keep what was built, record it for undo.
    func toolCancelled() {
        lastToolTile = nil
        commitStroke()
    }

    private func commitStroke() {
        guard let before = strokeBefore else { return }
        strokeBefore = nil
        let after = engine.mapSnapshot()
        var indices = [Int32](), old = [UInt16](), new = [UInt16]()
        before.withUnsafeBytes { (b: UnsafeRawBufferPointer) in
            after.withUnsafeBytes { (a: UnsafeRawBufferPointer) in
                let bv = b.bindMemory(to: UInt16.self), av = a.bindMemory(to: UInt16.self)
                for i in 0..<min(bv.count, av.count) where bv[i] != av[i] {
                    indices.append(Int32(i)); old.append(bv[i]); new.append(av[i])
                }
            }
        }
        guard !indices.isEmpty else { return }
        let name = ToolInfo.all.first(where: { $0.tool == tool })?.name ?? ""
        let edit = MapEdit(indices: indices.withUnsafeBufferPointer { Data(buffer: $0) },
                           before: old.withUnsafeBufferPointer { Data(buffer: $0) },
                           after: new.withUnsafeBufferPointer { Data(buffer: $0) },
                           cost: strokeFunds - engine.funds,
                           actionName: name)
        registerUndo(edit, isRedo: false)
    }

    /// Registers the inverse of `edit` (undo restores `before`, redo restores `after`).
    private func registerUndo(_ edit: MapEdit, isRedo: Bool) {
        guard let um = undoManager else { return }
        um.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.apply(edit, undoing: !isRedo)
                model.registerUndo(edit, isRedo: !isRedo)
            }
        }
        um.setActionName(edit.actionName)
        undoRevision += 1
    }

    private func apply(_ edit: MapEdit, undoing: Bool) {
        engine.writeCells(edit.indices, values: undoing ? edit.before : edit.after)
        engine.adjustFunds(undoing ? edit.cost : -edit.cost)
        zoneStatus = nil
        needsRender = true
        render()
        refreshState()
        undoRevision += 1
    }

    func undo() { undoManager?.undo(); undoRevision += 1 }
    func redo() { undoManager?.redo(); undoRevision += 1 }
    var canUndo: Bool { _ = undoRevision; return undoManager?.canUndo ?? false }
    var canRedo: Bool { _ = undoRevision; return undoManager?.canRedo ?? false }

    private func applyTool(x: Int, y: Int) {
        lastToolTile = (x, y)
        let result = engine.apply(tool, x: x, y: y)
        switch result {
        case .OK:
            playToolSound()
        case .noMoney:
            postMessage(index: 33, x: -1, y: -1, important: false)
            playSound("Sorry")
        case .needBulldoze:
            postMessage(index: 34, x: -1, y: -1, important: false)
            playSound("UhUh")
        default:
            break
        }
        needsRender = true
        render()
        refreshState()
    }

    func triggerDisaster(_ d: MPDisaster) {
        engine.triggerDisaster(d)
        needsRender = true
    }

    // MARK: Modal helpers

    func pauseForModal() {
        if speedBeforeModal == nil { speedBeforeModal = speed }
        speed = .paused
    }

    func resumeAfterModal() {
        if let s = speedBeforeModal { speed = s }
        speedBeforeModal = nil
        refreshState()
    }

    func focus(on message: GameMessage) {
        guard message.hasLocation else { return }
        focusRequest = FocusRequest(x: message.x, y: message.y)
    }

    private func postMessage(index: Int, x: Int, y: Int, important: Bool) {
        guard let text = GameText.message(index) else { return }
        if let last = latestMessage, last.text == text, !important { return }
        let m = GameMessage(text: text, important: important, x: x, y: y)
        latestMessage = m
        messages.insert(m, at: 0)
        if messages.count > 50 { messages.removeLast(messages.count - 50) }
        if important && m.hasLocation { focusRequest = FocusRequest(x: x, y: y) }
    }

    // MARK: Sound

    private func playToolSound() {
        let name: String
        switch tool {
        case .residential: name = "res"
        case .commercial: name = "zone"
        case .industrial: name = "ind"
        case .fireStation: name = "fire"
        case .policeStation: name = "police"
        case .wire: name = "wire"
        case .bulldozer: name = "bulldozer"
        case .railroad: name = "rail"
        case .road: name = "road"
        case .stadium: name = "stadium"
        case .park: name = "park"
        case .seaport: name = "seaport"
        case .coalPower: name = "coal"
        case .nuclearPower: name = "build"
        case .airport: name = "airport"
        default: return
        }
        playSound(name)
    }

    func playSound(_ name: String) {
        guard soundEnabled else { return }
        let now = Date()
        if let last = lastSoundTime[name], now.timeIntervalSince(last) < 0.12 { return }
        lastSoundTime[name] = now
        if players[name] == nil,
           let url = Bundle.main.url(forResource: name, withExtension: "mp3", subdirectory: "sounds") {
            players[name] = try? AVAudioPlayer(contentsOf: url)
            players[name]?.prepareToPlay()
        }
        guard let p = players[name] else { return }
        p.currentTime = 0
        p.play()
    }
}

// MARK: - Engine delegate

extension GameModel: MPEngineDelegate {
    nonisolated func engineSendMessage(_ messageIndex: Int, x: Int, y: Int, important: Bool) {
        MainActor.assumeIsolated { postMessage(index: messageIndex, x: x, y: y, important: important) }
    }

    nonisolated func engineMakeSound(_ sound: String, channel: String) {
        MainActor.assumeIsolated { playSound(sound) }
    }

    nonisolated func engineZoneStatusCategory(_ category: Int, population: Int, landValue: Int, crime: Int,
                                              pollution: Int, growth: Int, x: Int, y: Int) {
        MainActor.assumeIsolated {
            zoneStatus = ZoneStatus(category: GameText.tileCategory(category),
                                    population: GameText.level(population),
                                    landValue: GameText.level(landValue),
                                    crime: GameText.level(crime),
                                    pollution: GameText.level(pollution),
                                    growth: GameText.level(growth),
                                    x: x, y: y)
            playSound("query")
        }
    }

    nonisolated func engineShowBudget() {
        MainActor.assumeIsolated {
            if !showBudget { showBudget = true }
        }
    }

    nonisolated func engineDidWin() {
        MainActor.assumeIsolated { alert = .won }
    }

    nonisolated func engineDidLose() {
        MainActor.assumeIsolated { alert = .lost }
    }

    nonisolated func engineEarthquake(_ strength: Int) {
        MainActor.assumeIsolated { playSound("rumble") }
    }
}
