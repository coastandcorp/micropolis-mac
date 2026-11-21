// GameText.swift — UI and engine message strings (English / Japanese).
// Part of a modified version of Micropolis (GPL-3.0).

import Foundation

enum Lang {
    /// Uses the same language macOS picked for the app's menus and panels
    /// (honours the per-app language in System Settings; anything other than
    /// Japanese falls back to English).
    static let isJapanese: Bool = Bundle.main.preferredLocalizations.first?.hasPrefix("ja") ?? false
}

/// Pick the English or Japanese variant.
func L(_ en: String, _ ja: String) -> String { Lang.isJapanese ? ja : en }

enum GameText {
    /// Engine message numbers start at 1 (MESSAGE_NEED_MORE_RESIDENTIAL).
    static func message(_ index: Int) -> String? {
        let list = Lang.isJapanese ? messagesJA : messagesEN
        guard index >= 1, index <= list.count else { return nil }
        return list[index - 1]
    }

    static let messagesEN = [
        "More residential zones needed.", "More commercial zones needed.", "More industrial zones needed.",
        "More roads required.", "Inadequate rail system.", "Build a Power Plant.",
        "Residents demand a Stadium.", "Industry requires a Sea Port.", "Commerce requires an Airport.",
        "Pollution very high.", "Crime very high.", "Frequent traffic jams reported.",
        "Citizens demand a Fire Department.", "Citizens demand a Police Department.",
        "Blackouts reported. Check power map.", "Citizens upset. The tax rate is too high.",
        "Roads deteriorating, due to lack of funds.", "Fire departments need funding.",
        "Police departments need funding.", "Fire reported!", "A Monster has been sighted!!",
        "Tornado reported!!", "Major earthquake reported!!!", "A plane has crashed!",
        "Shipwreck reported!", "A train crashed!", "A helicopter crashed!",
        "Unemployment rate is high.", "YOUR CITY HAS GONE BROKE!", "Firebombing reported!",
        "Need more parks.", "Explosion detected!", "Insufficient funds to build that.",
        "Area must be bulldozed first.", "Population has reached 2,000.",
        "Population has reached 10,000.", "Population has reached 50,000.",
        "Population has reached 100,000.", "Population has reached 500,000.",
        "Brownouts, build another Power Plant.", "Heavy Traffic reported.", "Flooding reported!!",
        "A Nuclear Meltdown has occurred!!!", "They're rioting in the streets!!", "End of Demo!!",
        "No Sound Server!", "No Multi Player License!!", "Started a New City.", "Restored a Saved City.",
    ]

    static let messagesJA = [
        "住宅地が不足しています。", "商業地が不足しています。", "工業地が不足しています。",
        "道路が足りません。", "鉄道網が不十分です。", "発電所を建設してください。",
        "住民がスタジアムを求めています。", "工業には港が必要です。", "商業には空港が必要です。",
        "汚染がひどい状態です。", "犯罪が多発しています。", "交通渋滞が頻発しています。",
        "住民が消防署を求めています。", "住民が警察署を求めています。",
        "停電が発生しています。電力マップを確認してください。", "税率が高すぎて住民が不満です。",
        "予算不足で道路が傷んでいます。", "消防署の予算が足りません。",
        "警察署の予算が足りません。", "火災発生!", "怪獣が目撃されました!!",
        "竜巻発生!!", "大地震発生!!!", "飛行機が墜落しました!",
        "船が難破しました!", "列車が衝突しました!", "ヘリコプターが墜落しました!",
        "失業率が高くなっています。", "市の財政が破綻しました!", "爆撃を受けています!",
        "公園が足りません。", "爆発が起きました!", "資金が足りません。",
        "先に更地にする必要があります。", "人口が2,000人に達しました。",
        "人口が10,000人に達しました。", "人口が50,000人に達しました。",
        "人口が100,000人に達しました。", "人口が500,000人に達しました。",
        "電力不足です。発電所を増やしてください。", "交通量が非常に多くなっています。", "洪水発生!!",
        "原子炉がメルトダウンしました!!!", "暴動が起きています!!", "デモ版はここまでです!!",
        "サウンドが使えません!", "マルチプレイのライセンスがありません!!", "新しい都市を始めました。", "保存した都市を読み込みました。",
    ]

    /// Index 1...27 (stri.219)
    static func tileCategory(_ i: Int) -> String {
        let en = ["Clear", "Water", "Trees", "Rubble", "Flood", "Radioactive Waste", "Fire", "Road", "Power",
                  "Rail", "Residential", "Commercial", "Industrial", "Seaport", "Airport", "Coal Power",
                  "Fire Department", "Police Department", "Stadium", "Nuclear Power", "Draw Bridge",
                  "Radar Dish", "Fountain", "Industrial", "Steelers 38  Bears 3", "Draw Bridge", "Ur 238"]
        let ja = ["空き地", "水", "森", "がれき", "洪水", "放射性廃棄物", "火災", "道路", "電線",
                  "鉄道", "住宅地", "商業地", "工業地", "港", "空港", "石炭火力発電所",
                  "消防署", "警察署", "スタジアム", "原子力発電所", "跳ね橋",
                  "レーダー", "噴水", "工業地", "試合中 38対3", "跳ね橋", "ウラン238"]
        let list = Lang.isJapanese ? ja : en
        return (i >= 1 && i <= list.count) ? list[i - 1] : "?"
    }

    /// Index 1...20 (stri.202)
    static func level(_ i: Int) -> String {
        let en = ["Low", "Medium", "High", "Very High", "Slum", "Lower Class", "Middle Class", "High",
                  "Safe", "Light", "Moderate", "Dangerous", "None", "Moderate", "Heavy", "Very Heavy",
                  "Declining", "Stable", "Slow Growth", "Fast Growth"]
        let ja = ["低い", "普通", "高い", "非常に高い", "スラム", "低所得層", "中間層", "高所得層",
                  "安全", "少ない", "普通", "危険", "なし", "普通", "ひどい", "非常にひどい",
                  "衰退", "安定", "ゆるやかに成長", "急成長"]
        let list = Lang.isJapanese ? ja : en
        return (i >= 1 && i <= list.count) ? list[i - 1] : "?"
    }

    static func problem(_ i: Int) -> String {
        let en = ["Crime", "Pollution", "Housing Costs", "Taxes", "Traffic", "Unemployment", "Fires"]
        let ja = ["犯罪", "汚染", "住宅費", "税金", "交通", "失業", "火災"]
        let list = Lang.isJapanese ? ja : en
        return (i >= 0 && i < list.count) ? list[i] : "?"
    }

    static func cityClass(_ i: Int) -> String {
        let en = ["Village", "Town", "City", "Capital", "Metropolis", "Megalopolis"]
        let ja = ["村", "町", "市", "首都", "大都市", "巨大都市"]
        let list = Lang.isJapanese ? ja : en
        return (i >= 0 && i < list.count) ? list[i] : "?"
    }

    static let monthsEN = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    static func date(year: Int, month: Int) -> String {
        Lang.isJapanese ? "\(year)年\(month + 1)月" : "\(monthsEN[max(0, min(11, month))]) \(year)"
    }

    struct Scenario: Identifiable {
        let id: Int
        let name: String
        let tagline: String
        let year: Int
    }

    static let scenarios: [Scenario] = [
        .init(id: 1, name: L("Dullsville", "ダルズビル"), tagline: L("Boredom", "退屈"), year: 1900),
        .init(id: 2, name: L("San Francisco", "サンフランシスコ"), tagline: L("Earthquake", "地震"), year: 1906),
        .init(id: 3, name: L("Hamburg", "ハンブルク"), tagline: L("Bombing", "爆撃"), year: 1944),
        .init(id: 4, name: L("Bern", "ベルン"), tagline: L("Traffic", "交通渋滞"), year: 1965),
        .init(id: 5, name: L("Tokyo", "東京"), tagline: L("Monster Attack", "怪獣襲来"), year: 1957),
        .init(id: 6, name: L("Detroit", "デトロイト"), tagline: L("Crime", "犯罪"), year: 1972),
        .init(id: 7, name: L("Boston", "ボストン"), tagline: L("Nuclear Meltdown", "原発事故"), year: 2010),
        .init(id: 8, name: L("Rio de Janeiro", "リオデジャネイロ"), tagline: L("Coastal Flooding", "沿岸洪水"), year: 2047),
    ]
}
