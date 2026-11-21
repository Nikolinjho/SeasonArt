import Foundation

enum WinterTreeHeight: String, Codable, CaseIterable {
    case short, standard, tall

    var title: String {
        switch self {
        case .short: "Маленькая"
        case .standard: "Средняя"
        case .tall: "Высокая"
        }
    }

    var size: CGSize {
        let heights: [Self: CGFloat] = [.short: 124, .standard: 180, .tall: 252]
        let height = heights[self] ?? 180
        return CGSize(width: height * 0.72, height: height)
    }
}

enum WinterTreeTopper: String, Codable, CaseIterable {
    case star, snowflake, bow, bell, heart, finial

    var title: String {
        switch self {
        case .star: "Звезда"
        case .snowflake: "Снежинка"
        case .bow: "Бант"
        case .bell: "Колокольчик"
        case .heart: "Сердце"
        case .finial: "Шпиль"
        }
    }
}

enum WinterTreeOrnament: String, Codable, CaseIterable {
    case baubles, lights, garland, candy, bells, gingerbread, bows, stars

    var title: String {
        switch self {
        case .baubles: "Шары"
        case .lights: "Огоньки"
        case .garland: "Мишура"
        case .candy: "Леденцы"
        case .bells: "Колокольчики"
        case .gingerbread: "Пряники"
        case .bows: "Банты"
        case .stars: "Звёздочки"
        }
    }
}

struct WinterTreeDecorations: Codable, Equatable {
    var height: WinterTreeHeight = .standard
    var topper: WinterTreeTopper = .star
    var ornaments: Set<WinterTreeOrnament> = [.baubles, .lights]

    mutating func surprise() {
        topper = WinterTreeTopper.allCases.filter { $0 != topper }.randomElement() ?? .star
        ornaments = Set(WinterTreeOrnament.allCases.shuffled().prefix(Int.random(in: 2...4)))
    }
}
