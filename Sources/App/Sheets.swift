// Sheets.swift — new city, budget, evaluation and about screens.
// Part of a modified version of Micropolis (GPL-3.0).

import SwiftUI
import Charts

// MARK: - Sheet chrome

/// Title on top, buttons at the bottom, as plain views. (Toolbar items inside
/// a NavigationStack are not shown in macOS sheets, which hid "Open File…".)
struct SheetChrome<Content: View, Actions: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.headline)
                .padding(.vertical, 12)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack { actions }
                .padding(12)
        }
    }
}

// MARK: - New city

struct NewCityView: View {
    @Bindable var model: GameModel
    @Environment(\.dismiss) private var dismiss
    @State private var level = 0
    @State private var tab = 0
    // The importer lives on the sheet itself: a file panel requested by the
    // view underneath cannot appear while this sheet is shown.
    @State private var showImporter = false
    @State private var openFailed = false

    static let sampleCities: [(file: String, name: String)] = [
        ("haight", "Haight"), ("kyoto", "Kyoto"), ("kobe", "Kobe"), ("yokohama", "Yokohama"),
        ("kamakura", "Kamakura"), ("senri", "Senri"), ("kowloon", "Kowloon"), ("radial", "Radial"),
        ("linecity", "Line City"), ("happisle", "Happy Isle"), ("med_isle", "Med Isle"), ("southpac", "South Pacific"),
        ("bluebird", "Bluebird"), ("deadwood", "Deadwood"), ("finnigan", "Finnigan"), ("freds", "Freds"),
        ("joffburg", "Joffburg"), ("ndulls", "N. Dulls"), ("neatmap", "Neat Map"), ("splats", "Splats"),
        ("wetcity", "Wet City"), ("badnews", "Bad News"), ("bruce", "Bruce"),
    ]

    var body: some View {
        SheetChrome(title: L("Start a City", "都市をはじめる")) {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text(L("New Map", "新しい土地")).tag(0)
                    Text(L("Scenarios", "シナリオ")).tag(1)
                    Text(L("Sample Cities", "サンプル都市")).tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding()

                switch tab {
                case 0: newMap
                case 1: scenarios
                default: samples
                }
            }
        } actions: {
            Button(L("Open File…", "ファイルを開く…"), systemImage: "folder") { showImporter = true }
            Spacer()
            if model.hasCity {
                Button(L("Cancel", "キャンセル")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            } else {
                #if os(macOS)
                Button(L("Quit", "終了")) { quitApp() }
                #endif
            }
        }
        .frame(minWidth: 520, minHeight: 520)
        .interactiveDismissDisabled(!model.hasCity)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.micropolisCity, .data]) { result in
            guard case .success(let url) = result else { return }
            if model.loadCity(url: url) {
                dismiss()
            } else {
                openFailed = true
            }
        }
        .alert(L("Could not open this city file.", "この都市ファイルを開けませんでした。"), isPresented: $openFailed) {
            Button("OK", role: .cancel) {}
        }
        .onReceive(NotificationCenter.default.publisher(for: .micropolisCommand)) { note in
            if note.object as? String == "open" { showImporter = true }
        }
    }

    private var newMap: some View {
        Form {
            Section(L("Difficulty", "難易度")) {
                Picker(L("Difficulty", "難易度"), selection: $level) {
                    Text(L("Easy ($20,000)", "やさしい ($20,000)")).tag(0)
                    Text(L("Medium ($10,000)", "ふつう ($10,000)")).tag(1)
                    Text(L("Hard ($5,000)", "むずかしい ($5,000)")).tag(2)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section {
                Button {
                    model.newRandomCity(level: level)
                    dismiss()
                } label: {
                    Label(L("Generate Random Terrain and Start", "ランダムな地形で開始"), systemImage: "map")
                }
            } footer: {
                Text(L("Build roads, power and zones. Tip: one finger (or the mouse) builds, two fingers (or scroll / right-drag) move the map, pinch to zoom.",
                       "道路・電力・ゾーンを整備して都市を育てましょう。1本指(マウス)で建設、2本指(スクロール/右ドラッグ)で移動、ピンチで拡大縮小します。"))
            }
        }
        .formStyle(.grouped)
    }

    private var scenarios: some View {
        List(GameText.scenarios) { s in
            Button {
                model.loadScenario(s.id)
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    (BundleImages.image("scenarios/scenario_\(s.id).png") ?? Image(systemName: "map"))
                        .resizable()
                        .interpolation(.none)
                        .frame(width: 96, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.name).font(.headline)
                        Text("\(s.tagline) · \(String(s.year))").foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var samples: some View {
        List(Self.sampleCities, id: \.file) { c in
            Button {
                model.loadSampleCity(c.file)
                dismiss()
            } label: {
                HStack {
                    Image(systemName: "building.2")
                    Text(c.name)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Budget

struct BudgetView: View {
    @Bindable var model: GameModel
    @Environment(\.dismiss) private var dismiss
    @State private var tax = 7.0
    @State private var road = 1.0
    @State private var police = 1.0
    @State private var fire = 1.0
    @State private var autoBudget = true

    var body: some View {
        SheetChrome(title: L("Budget", "予算")) {
            Form {
                Section {
                    LabeledContent(L("Current Funds", "現在の資金"), value: formatMoney(model.engine.funds))
                    LabeledContent(L("Annual Tax Income", "年間税収"), value: formatMoney(model.engine.taxIncome))
                    VStack(alignment: .leading) {
                        LabeledContent(L("Tax Rate", "税率"), value: "\(Int(tax))%")
                        Slider(value: $tax, in: 0...20, step: 1)
                    }
                }
                Section(L("Funding", "予算配分")) {
                    fundingRow(L("Transportation", "交通"), requested: model.engine.roadRequested, value: $road)
                    fundingRow(L("Police", "警察"), requested: model.engine.policeRequested, value: $police)
                    fundingRow(L("Fire", "消防"), requested: model.engine.fireRequested, value: $fire)
                }
                Section {
                    Toggle(L("Auto Budget", "自動予算"), isOn: $autoBudget)
                } footer: {
                    Text(L("With auto budget on, all departments are fully funded every year while money lasts.",
                           "自動予算をオンにすると、資金がある限り毎年すべての部門に満額を配分します。"))
                }
            }
            .formStyle(.grouped)
        } actions: {
            Spacer()
            Button(L("Done", "完了")) { apply(); dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .frame(minWidth: 420, minHeight: 480)
        .onAppear {
            tax = Double(model.engine.taxRate)
            road = model.engine.roadPercent
            police = model.engine.policePercent
            fire = model.engine.firePercent
            autoBudget = model.engine.autoBudget
        }
    }

    private func fundingRow(_ title: String, requested: Int, value: Binding<Double>) -> some View {
        VStack(alignment: .leading) {
            LabeledContent(title) {
                Text("\(Int((value.wrappedValue * 100).rounded()))% · \(formatMoney(Int(Double(requested) * value.wrappedValue))) / \(formatMoney(requested))")
                    .monospacedDigit()
            }
            Slider(value: value, in: 0...1, step: 0.05)
        }
    }

    private func apply() {
        model.engine.taxRate = Int(tax)
        model.engine.roadPercent = road
        model.engine.policePercent = police
        model.engine.firePercent = fire
        model.engine.autoBudget = autoBudget
        model.refreshState()
    }
}

// MARK: - Evaluation

struct EvaluationView: View {
    let model: GameModel
    @Environment(\.dismiss) private var dismiss
    @State private var graphKind = 0

    private struct Point: Identifiable {
        let id: Int
        let series: String
        let value: Int
    }

    var body: some View {
        SheetChrome(title: L("Evaluation", "評価")) {
            Form {
                Section(L("Public Opinion", "世論")) {
                    LabeledContent(L("Approval of the Mayor", "市長の支持率"), value: "\(model.engine.approval)%")
                    let problems = model.engine.topProblems.map { $0.intValue }
                    if problems.isEmpty {
                        Text(L("No major problems.", "大きな問題はありません。")).foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(problems.enumerated()), id: \.offset) { i, p in
                            Text("\(i + 1). \(GameText.problem(p))")
                        }
                    }
                }
                Section(L("Statistics", "統計")) {
                    LabeledContent(L("Population", "人口"), value: model.population.formatted())
                    LabeledContent(L("Category", "規模"), value: GameText.cityClass(model.cityClass))
                    LabeledContent(L("Assessed Value", "資産評価額"), value: formatMoney(model.engine.assessedValue))
                    LabeledContent(L("Overall City Score", "総合スコア"), value: "\(model.engine.score) / 1000")
                }
                Section(L("History (10 years)", "推移(10年)")) {
                    Picker("", selection: $graphKind) {
                        Text(L("Zones", "ゾーン")).tag(0)
                        Text(L("Money", "資金")).tag(1)
                        Text(L("Crime & Pollution", "犯罪と汚染")).tag(2)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Chart(points) { p in
                        LineMark(x: .value("t", p.id), y: .value("v", p.value))
                            .foregroundStyle(by: .value("series", p.series))
                    }
                    .chartXAxis(.hidden)
                    .frame(height: 180)
                }
            }
            .formStyle(.grouped)
        } actions: {
            Spacer()
            Button(L("Done", "完了")) { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .frame(minWidth: 460, minHeight: 600)
    }

    private var points: [Point] {
        let kinds: [(Int, String)]
        switch graphKind {
        case 0: kinds = [(0, L("Residential", "住宅")), (1, L("Commercial", "商業")), (2, L("Industrial", "工業"))]
        case 1: kinds = [(3, L("Cash Flow", "収支"))]
        default: kinds = [(4, L("Crime", "犯罪")), (5, L("Pollution", "汚染"))]
        }
        var out: [Point] = []
        for (kind, name) in kinds {
            let h = model.engine.history(ofKind: kind).map { $0.intValue }
            // Newest value is at index 0; plot oldest → newest.
            for (i, v) in h.reversed().enumerated() {
                out.append(Point(id: i, series: name, value: v))
            }
        }
        return out
    }
}

// MARK: - About

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    /// e.g. "Version 1.0 (1)" / "バージョン 1.0 (1)", read from Info.plist.
    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return L("Version \(version) (\(build))", "バージョン \(version) (\(build))")
    }

    var body: some View {
        SheetChrome(title: L("About", "このアプリについて")) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Micropolis").font(.largeTitle.bold())
                        Text(AboutView.versionText).foregroundStyle(.secondary)
                    }
                    Text(L("A native macOS port of the open-source Micropolis city simulator (MicropolisCore). This is a modified version and is not the original program.",
                           "オープンソースの都市シミュレーター Micropolis(MicropolisCore)を macOS 向けに移植した改変版です。オリジナルのプログラムではありません。"))
                    GroupBox(L("Trademark", "商標")) {
                        Text("Micropolis is a registered trademark of Micropolis Corporation (Micropolis GmbH) and is licensed here as a courtesy of the owner under the Micropolis Public Name License.")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Link("https://www.micropolis.com", destination: URL(string: "https://www.micropolis.com")!)
                    }
                    GroupBox(L("License", "ライセンス")) {
                        Text("""
                        Micropolis, Unix Version. Copyright (C) 1989 - 2007 Electronic Arts Inc.

                        This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

                        This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

                        ADDITIONAL TERMS per GNU GPL Section 7: No trademark or publicity rights are granted. This license does NOT give you any right, title or interest in the trademark SimCity or any other Electronic Arts trademark. You may not distribute any modification of this program using the trademark SimCity or claim any affiliation or association with Electronic Arts Inc. or its employees. You may not misrepresent the origins of this program; modified versions of the program must be marked as such and not identified as the original program.
                        """)
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Link(L("Source code (MicropolisCore)", "ソースコード(MicropolisCore)"),
                             destination: URL(string: "https://github.com/SimHacker/MicropolisCore")!)
                        Link("GNU GPL v3", destination: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!)
                    }
                }
                .padding()
                .textSelection(.enabled)
            }
        } actions: {
            Spacer()
            Button(L("Done", "完了")) { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .frame(minWidth: 480, minHeight: 520)
    }
}
