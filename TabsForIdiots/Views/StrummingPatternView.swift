import SwiftUI

struct StrummingPatternView: View {
    let pattern: StrummingPattern

    // Fixed absolute sizes, not proportional to the row's available width —
    // grouped strums always sit `shortGap` apart, spread-out strums always
    // sit `longGap` apart, everywhere in the app. Patterns without a real
    // short/long distinction (no bar-notation spacing) fall back to the
    // original uniform `defaultGap`, so they render unchanged.
    private let strokeWidth: CGFloat = 18
    private let defaultGap: CGFloat = 8
    private let shortGap: CGFloat = 4
    private let longGap: CGFloat = 16

    private func gapWidth(afterIndex idx: Int, longAfter: [Bool]) -> CGFloat {
        guard longAfter.contains(true) else { return defaultGap }
        return longAfter[idx] ? longGap : shortGap
    }

    // A pause is a lead-in rest, not a strike — render it as plain empty
    // space rather than a "·" symbol with a "-" label underneath.
    @ViewBuilder
    private func strokeContent(_ stroke: StrummingPattern.Stroke) -> some View {
        if stroke == .pause {
            Color.clear
        } else {
            VStack(spacing: 2) {
                Text(stroke.symbol)
                    .font(.system(size: 18))
                    .foregroundStyle(stroke.isDown ? Color.primary : Color.blue)
                Text(stroke.rawValue)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    var body: some View {
        let longAfter = pattern.longGapAfter
        VStack(alignment: .leading, spacing: 2) {
            Text(pattern.name).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 0) {
                ForEach(Array(pattern.strokes.enumerated()), id: \.offset) { idx, stroke in
                    // A pause has no glyph of its own; giving it a full stroke-width
                    // column too would make the lead-in gap wider than a same-tier
                    // gap between two real strokes, so it collapses to width 0 and
                    // the gap after it is the only space rendered.
                    strokeContent(stroke)
                        .frame(width: stroke == .pause ? 0 : strokeWidth)
                    if idx < pattern.strokes.count - 1 {
                        Spacer().frame(width: gapWidth(afterIndex: idx, longAfter: longAfter))
                    }
                }
            }
        }
    }
}
