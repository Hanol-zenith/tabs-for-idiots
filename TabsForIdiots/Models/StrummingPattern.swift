import Foundation

struct StrummingPattern: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var strokes: [Stroke]

    enum Stroke: String, Codable, CaseIterable {
        case down      = "D"
        case up        = "U"
        case downMuted = "d"
        case upMuted   = "u"
        case pause     = "-"

        var symbol: String {
            switch self {
            case .down:      return "↓"
            case .up:        return "↑"
            case .downMuted: return "↡"
            case .upMuted:   return "↟"
            case .pause:     return "·"
            }
        }

        var isDown: Bool { self == .down || self == .downMuted }
    }

    init(id: UUID = UUID(), name: String, strokes: [Stroke]) {
        self.id = id
        self.name = name
        self.strokes = strokes
    }
}
