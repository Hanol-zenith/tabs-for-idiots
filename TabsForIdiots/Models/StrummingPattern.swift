import Foundation

struct StrummingPattern: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var strokes: [Stroke]
    // Duration of each stroke's slot in quarter notes (must sum to 4 for 4/4).
    // Empty array = equal spacing across the measure.
    var intervals: [Double]

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

    // Whether the gap AFTER each stroke (except the last) should render as the
    // "long" tier vs the "short" tier, derived from `intervals`. All `false`
    // when there's no real short/long distinction (empty or uniform
    // intervals), so callers can fall back to a single default gap.
    var longGapAfter: [Bool] {
        guard intervals.count == strokes.count, strokes.count > 1 else {
            return Array(repeating: false, count: max(strokes.count - 1, 0))
        }
        let distinct = Array(Set(intervals)).sorted()
        guard let lo = distinct.first, let hi = distinct.last, lo != hi else {
            return Array(repeating: false, count: strokes.count - 1)
        }
        let threshold = (lo + hi) / 2
        return intervals.dropLast().map { $0 > threshold }
    }

    init(id: UUID = UUID(), name: String, strokes: [Stroke], intervals: [Double] = []) {
        self.id = id
        self.name = name
        self.strokes = strokes
        self.intervals = intervals
    }

    // Backward-compatible decoder: old JSON without "intervals" defaults to equal spacing.
    enum CodingKeys: String, CodingKey { case id, name, strokes, intervals }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try  c.decode(UUID.self,    forKey: .id)
        name      = try  c.decode(String.self,  forKey: .name)
        strokes   = try  c.decode([Stroke].self, forKey: .strokes)
        intervals = (try? c.decodeIfPresent([Double].self, forKey: .intervals)) ?? []
    }
}
