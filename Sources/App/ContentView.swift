// ContentView.swift — main game screen shared by macOS and iPadOS.
// Part of a modified version of Micropolis (GPL-3.0).

import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
typealias PlatformImage = NSImage
#else
typealias PlatformImage = UIImage
#endif

@MainActor
enum BundleImages {
    private static var cache: [String: Image] = [:]

    static func image(_ relativePath: String) -> Image? {
        if let i = cache[relativePath] { return i }
        guard let path = Bundle.main.resourcePath.map({ ($0 as NSString).appendingPathComponent(relativePath) }),
              let img = PlatformImage(contentsOfFile: path) else { return nil }
        #if os(macOS)
        let i = Image(nsImage: img)
        #else
        let i = Image(uiImage: img)
        #endif
        cache[relativePath] = i
        return i
    }
}

struct ToolInfo: Identifiable {
    let tool: MPTool
    let icon: String
    let name: String
    var id: Int { tool.rawValue }
    var cost: Int { MPEngine.cost(of: tool) }

    static let all: [ToolInfo] = [
        .init(tool: .query, icon: "query", name: L("Query", "調査")),
        .init(tool: .bulldozer, icon: "bulldozer", name: L("Bulldozer", "ブルドーザー")),
        .init(tool: .road, icon: "road", name: L("Road", "道路")),
        .init(tool: .railroad, icon: "railroad", name: L("Rail", "鉄道")),
        .init(tool: .wire, icon: "wire", name: L("Power Line", "電線")),
        .init(tool: .park, icon: "park", name: L("Park", "公園")),
        .init(tool: .residential, icon: "residential", name: L("Residential", "住宅地")),
        .init(tool: .commercial, icon: "commercial", name: L("Commercial", "商業地")),
        .init(tool: .industrial, icon: "industrial", name: L("Industrial", "工業地")),
        .init(tool: .policeStation, icon: "policestation", name: L("Police", "警察署")),
        .init(tool: .fireStation, icon: "firestation", name: L("Fire Dept.", "消防署")),
        .init(tool: .stadium, icon: "stadium", name: L("Stadium", "スタジアム")),
        .init(tool: .coalPower, icon: "coalpower", name: L("Coal Power", "石炭発電所")),
        .init(tool: .nuclearPower, icon: "nuclearpower", name: L("Nuclear Power", "原子力発電所")),
        .init(tool: .seaport, icon: "seaport", name: L("Seaport", "港")),
        .init(tool: .airport, icon: "airport", name: L("Airport", "空港")),
    ]
}

struct OverlayInfo: Identifiable {
    let overlay: MPOverlay
    let name: String
    var id: Int { overlay.rawValue }

    static let all: [OverlayInfo] = [
        .init(overlay: .none, name: L("None", "なし")),
        .init(overlay: .power, name: L("Power Grid", "電力網")),
        .init(overlay: .population, name: L("Population Density", "人口密度")),
        .init(overlay: .traffic, name: L("Traffic", "交通量")),
        .init(overlay: .pollution, name: L("Pollution", "汚染")),
        .init(overlay: .crime, name: L("Crime", "犯罪")),
        .init(overlay: .landValue, name: L("Land Value", "地価")),
        .init(overlay: .fireCoverage, name: L("Fire Coverage", "消防の範囲")),
        .init(overlay: .policeCoverage, name: L("Police Coverage", "警察の範囲")),
    ]
}

func formatMoney(_ v: Int) -> String {
    "$" + v.formatted(.number.grouping(.automatic))
}

struct ContentView: View {
    @Bindable var model: GameModel
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var exportDocument: CityDocument?
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(model: model)
                .frame(width: 196)
                .background(.bar)
            Divider()
            ZStack(alignment: .bottom) {
                MapView(model: model)
                    .ignoresSafeArea(edges: [.bottom])
                VStack(spacing: 8) {
                    if let status = model.zoneStatus {
                        ZoneStatusCard(status: status) { model.zoneStatus = nil }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    MessageBar(model: model)
                }
                .padding(12)
                .animation(.snappy, value: model.zoneStatus?.id)
            }
        }
        .toolbar { toolbarContent }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationTitle(model.hasCity ? model.cityName : "Micropolis")
        .sheet(isPresented: $model.showNewCity) {
            NewCityView(model: model)
        }
        .sheet(isPresented: $model.showBudget, onDismiss: { model.resumeAfterModal() }) {
            BudgetView(model: model)
                .onAppear { model.pauseForModal() }
        }
        .sheet(isPresented: $model.showEvaluation) {
            EvaluationView(model: model)
        }
        .sheet(isPresented: $model.showAbout) {
            AboutView()
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.micropolisCity, .data]) { result in
            if case .success(let url) = result {
                if !model.loadCity(url: url) {
                    model.alert = .toolError(L("Could not open this city file.", "この都市ファイルを開けませんでした。"))
                } else {
                    model.showNewCity = false
                }
            }
        }
        .fileExporter(isPresented: $showExporter, document: exportDocument, contentType: .micropolisCity,
                      defaultFilename: model.cityName.isEmpty ? "City" : model.cityName) { _ in }
        .alert(item: $model.alert) { alert in
            switch alert {
            case .won:
                return Alert(title: Text(L("You won!", "クリア!")),
                             message: Text(L("You met the goal of this scenario.", "シナリオの目標を達成しました。")))
            case .lost:
                return Alert(title: Text(L("You lost", "失敗")),
                             message: Text(L("The citizens have run you out of office.", "市長を解任されました。")))
            case .toolError(let msg):
                return Alert(title: Text(msg))
            }
        }
        .onChange(of: undoManager, initial: true) { _, um in
            model.undoManager = um
        }
        .onAppear {
            #if DEBUG
            // Test hook: `-demoCity haight` loads a sample city, `-demoScenario 5` a scenario.
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-demoCity"), i + 1 < args.count {
                model.loadSampleCity(args[i + 1])
            } else if let i = args.firstIndex(of: "-demoScenario"), i + 1 < args.count, let n = Int(args[i + 1]) {
                model.loadScenario(n)
            }
            if args.contains("-demoOverlay") { model.overlay = .power }
            #if os(macOS)
            if args.contains("-demoQuit") {
                // Test hook: ask the app to quit (same path as ⌘Q) after 4 s.
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { quitApp() }
            }
            #endif
            if let i = args.firstIndex(of: "-demoSheet"), i + 1 < args.count {
                switch args[i + 1] {
                case "budget": model.showBudget = true
                case "evaluation": model.showEvaluation = true
                case "about": model.showAbout = true
        case "dismissSheets":
            // Quitting: AppKit will not terminate while a sheet is attached.
            model.showNewCity = false
            model.showBudget = false
            model.showEvaluation = false
            model.showAbout = false
            showImporter = false
            showExporter = false
                default: break
                }
            }
            #endif
            // Resume the autosaved city (saved on quit and once a minute).
            if !model.hasCity { model.restoreAutosave() }
            if !model.hasCity { model.showNewCity = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .micropolisCommand)) { note in
            handleCommand(note.object as? String)
        }
        .onOpenURL { url in
            // Double-clicked .cty in Finder, or dropped on the app icon.
            guard url.isFileURL else { return }
            if model.loadCity(url: url) {
                model.showNewCity = false
            } else {
                model.alert = .toolError(L("Could not open this city file.", "この都市ファイルを開けませんでした。"))
            }
        }
    }

    private func handleCommand(_ cmd: String?) {
        switch cmd {
        case "new": model.showNewCity = true
        case "open":
            // While the start sheet is up it shows its own file panel.
            if !model.showNewCity { showImporter = true }
        case "save": save()
        case "budget": model.showBudget = true
        case "evaluation": model.showEvaluation = true
        case "about": model.showAbout = true
        case "dismissSheets":
            // Quitting: AppKit will not terminate while a sheet is attached.
            model.showNewCity = false
            model.showBudget = false
            model.showEvaluation = false
            model.showAbout = false
            showImporter = false
            showExporter = false
        default: break
        }
    }

    private func save() {
        guard model.hasCity, let data = model.cityData() else { return }
        exportDocument = CityDocument(data: data)
        showExporter = true
    }

    // MARK: Toolbar

    // Each toolbar menu is its own View so that the frequently changing game
    // state (funds, date, demand) does not rebuild an open menu, which made
    // submenus flicker and close.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            UndoButtons(model: model)
        }
        ToolbarItem(placement: .primaryAction) {
            OverlayMenu(model: model)
        }
        ToolbarItem(placement: .primaryAction) {
            DisasterMenu(model: model)
        }
        ToolbarItem(placement: .primaryAction) {
            SimulationMenu(model: model)
        }
        ToolbarItem(placement: .primaryAction) {
            CityMenu(model: model, onOpen: { showImporter = true }, onSave: { save() })
        }
    }
}

// MARK: - Toolbar menus

struct UndoButtons: View {
    let model: GameModel

    var body: some View {
        Button {
            model.undo()
        } label: {
            Label(L("Undo", "取り消す"), systemImage: "arrow.uturn.backward")
        }
        .disabled(!model.canUndo)
        .help(L("Undo", "取り消す") + " (⌘Z)")
        Button {
            model.redo()
        } label: {
            Label(L("Redo", "やり直す"), systemImage: "arrow.uturn.forward")
        }
        .disabled(!model.canRedo)
        .help(L("Redo", "やり直す") + " (⇧⌘Z)")
    }
}

struct OverlayMenu: View {
    @Bindable var model: GameModel

    var body: some View {
        Menu {
            Picker(L("Map Overlay", "マップ表示"), selection: $model.overlay) {
                ForEach(OverlayInfo.all) { o in Text(o.name).tag(o.overlay) }
            }
            .pickerStyle(.inline)
        } label: {
            Label(L("Map Overlay", "マップ表示"), systemImage: model.overlay == .none ? "map" : "map.fill")
        }
        .menuIndicator(.hidden)
        .help(L("Map Overlay", "マップ表示"))
    }
}

struct SimulationMenu: View {
    @Bindable var model: GameModel

    var body: some View {
        Menu {
            Picker(L("Speed", "速度"), selection: $model.speed) {
                ForEach(SimSpeed.allCases) { s in
                    Label(s.title, systemImage: s.symbol).tag(s)
                }
            }
            .pickerStyle(.inline)
            Divider()
            Toggle(L("Sound", "サウンド"), isOn: $model.soundEnabled)
        } label: {
            Label(model.speed.title, systemImage: model.speed.symbol)
        }
        .menuIndicator(.hidden)
        .help(L("Speed", "速度"))
    }
}

struct DisasterMenu: View {
    let model: GameModel

    var body: some View {
        Menu {
            DisasterButtons(model: model)
        } label: {
            Label(L("Disasters", "災害"), systemImage: "tornado")
        }
        .menuIndicator(.hidden)
        .help(L("Disasters", "災害"))
    }
}

struct DisasterButtons: View {
    let model: GameModel

    var body: some View {
        Button(L("Fire", "火災")) { model.triggerDisaster(.fire) }
        Button(L("Flood", "洪水")) { model.triggerDisaster(.flood) }
        Button(L("Tornado", "竜巻")) { model.triggerDisaster(.tornado) }
        Button(L("Earthquake", "地震")) { model.triggerDisaster(.earthquake) }
        Button(L("Monster", "怪獣")) { model.triggerDisaster(.monster) }
        Button(L("Meltdown", "メルトダウン")) { model.triggerDisaster(.meltdown) }
    }
}

struct CityMenu: View {
    let model: GameModel
    let onOpen: () -> Void
    let onSave: () -> Void

    var body: some View {
        Menu {
            Button(L("Budget…", "予算…"), systemImage: "dollarsign.circle") { model.showBudget = true }
            Button(L("Evaluation…", "評価…"), systemImage: "chart.bar") { model.showEvaluation = true }
            Divider()
            Button(L("New City…", "新しい都市…"), systemImage: "plus") { model.showNewCity = true }
            Button(L("Open City…", "都市を開く…"), systemImage: "folder") { onOpen() }
            Button(L("Save City…", "都市を保存…"), systemImage: "square.and.arrow.down") { onSave() }
                .disabled(!model.hasCity)
            Divider()
            Button(L("About Micropolis", "Micropolis について"), systemImage: "info.circle") { model.showAbout = true }
        } label: {
            Label(L("City", "都市"), systemImage: "building.2")
        }
        .menuIndicator(.hidden)
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    let model: GameModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                cityInfo
                toolGrid
                if let tool = ToolInfo.all.first(where: { $0.tool == model.tool }) {
                    HStack {
                        Text(tool.name).font(.callout.weight(.semibold))
                        Spacer()
                        if tool.cost > 0 {
                            Text(formatMoney(tool.cost)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
                DemandMeter(r: model.demandR, c: model.demandC, i: model.demandI)
                miniMap
            }
            .padding(12)
        }
    }
    private var cityInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.hasCity ? model.cityName : "—")
                .font(.headline)
                .lineLimit(1)
            Label(model.dateText, systemImage: "calendar")
            Label(formatMoney(model.funds), systemImage: "banknote")
                .foregroundStyle(model.funds < 0 ? .red : .primary)
            Label("\(model.population.formatted()) · \(GameText.cityClass(model.cityClass))",
                  systemImage: "person.3.fill")
        }
        .font(.callout.monospacedDigit())
        .labelStyle(CompactLabelStyle())
    }

    private var toolGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: 4), count: 4), spacing: 4) {
            ForEach(ToolInfo.all) { info in
                Button {
                    model.tool = info.tool
                } label: {
                    (BundleImages.image("tools/tool_\(info.icon).png") ?? Image(systemName: "questionmark"))
                        .resizable()
                        .interpolation(.none)
                        .frame(width: 36, height: 36)
                        .padding(2)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(model.tool == info.tool ? Color.accentColor.opacity(0.35) : Color.clear))
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(model.tool == info.tool ? Color.accentColor : Color.clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .help(info.name)
                .accessibilityLabel(info.name)
            }
        }
    }

    private var miniMap: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("Overview", "全体マップ")).font(.caption).foregroundStyle(.secondary)
            if let img = model.miniMapImage {
                Image(decorative: img, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(CGFloat(MPWorldWidth) / CGFloat(MPWorldHeight), contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay {
                        GeometryReader { geo in
                            Color.clear.contentShape(Rectangle())
                                .onTapGesture { p in
                                    let x = Int(p.x / geo.size.width * CGFloat(MPWorldWidth))
                                    let y = Int(p.y / geo.size.height * CGFloat(MPWorldHeight))
                                    model.focusRequest = FocusRequest(x: x, y: y)
                                }
                        }
                    }
            }
        }
    }

}

// MARK: - Message bar

struct MessageBar: View {
    let model: GameModel
    @State private var showMessageLog = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: model.latestMessage?.important == true ? "exclamationmark.triangle.fill" : "info.circle")
                .foregroundStyle(model.latestMessage?.important == true ? .red : .secondary)
            Text(model.latestMessage?.text ?? L("Welcome to Micropolis.", "Micropolis へようこそ。"))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let m = model.latestMessage, m.hasLocation {
                Button(L("Go", "移動")) { model.focus(on: m) }
                    .buttonStyle(.borderless)
            }
            Button {
                showMessageLog.toggle()
            } label: {
                Image(systemName: "list.bullet")
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $showMessageLog) {
                MessageLogView(model: model)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .frame(maxWidth: 560)
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.frame(width: 18).foregroundStyle(.secondary)
            configuration.title
        }
    }
}

// MARK: - Demand meter

struct DemandMeter: View {
    let r: Int, c: Int, i: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("Demand", "需要")).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .center, spacing: 10) {
                bar("R", value: Double(r) / 2000, color: .green)
                bar("C", value: Double(c) / 1500, color: .blue)
                bar("I", value: Double(i) / 1500, color: .yellow)
            }
            .frame(height: 70)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Demand", "需要"))
    }

    private func bar(_ label: String, value: Double, color: Color) -> some View {
        let v = max(-1, min(1, value))
        return VStack(spacing: 2) {
            GeometryReader { geo in
                let half = geo.size.height / 2
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 2).fill(.quaternary)
                    Rectangle().fill(.secondary).frame(height: 1).offset(y: half)
                    Rectangle()
                        .fill(color)
                        .frame(height: abs(v) * half)
                        .offset(y: v >= 0 ? half - abs(v) * half : half)
                }
            }
            .frame(width: 18)
            Text(label).font(.caption2.bold())
        }
    }
}

// MARK: - Zone status

struct ZoneStatusCard: View {
    let status: ZoneStatus
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(status.category).font(.headline)
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 3) {
                row(L("Density", "人口密度"), status.population)
                row(L("Value", "地価"), status.landValue)
                row(L("Crime", "犯罪"), status.crime)
                row(L("Pollution", "汚染"), status.pollution)
                row(L("Growth", "成長"), status.growth)
            }
            .font(.callout)
        }
        .padding(12)
        .frame(maxWidth: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func row(_ k: String, _ v: String) -> some View {
        GridRow {
            Text(k).foregroundStyle(.secondary)
            Text(v)
        }
    }
}

struct MessageLogView: View {
    let model: GameModel

    var body: some View {
        List {
            if model.messages.isEmpty {
                Text(L("No messages yet.", "メッセージはまだありません。")).foregroundStyle(.secondary)
            }
            ForEach(model.messages) { m in
                Button {
                    model.focus(on: m)
                } label: {
                    HStack {
                        Image(systemName: m.important ? "exclamationmark.triangle.fill" : "info.circle")
                            .foregroundStyle(m.important ? .red : .secondary)
                        Text(m.text)
                        Spacer()
                        if m.hasLocation { Image(systemName: "location").foregroundStyle(.secondary) }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!m.hasLocation)
            }
        }
        .frame(minWidth: 340, minHeight: 300)
    }
}

// MARK: - City document

extension UTType {
    static let micropolisCity = UTType(exportedAs: "com.coastandcorp.micropolis.city")
}

struct CityDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.micropolisCity] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension Notification.Name {
    static let micropolisCommand = Notification.Name("micropolisCommand")
}
