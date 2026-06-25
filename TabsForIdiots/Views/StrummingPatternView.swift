import SwiftUI

struct StrummingPatternView: View {
    let pattern: StrummingPattern

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(pattern.name).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(Array(pattern.strokes.enumerated()), id: \.offset) { _, stroke in
                    Text(stroke.symbol)
                        .font(.system(size: 18))
                        .foregroundStyle(stroke.isDown ? Color.primary : Color.blue)
                        .frame(width: 18, alignment: .center)
                }
            }
            HStack(spacing: 8) {
                ForEach(Array(pattern.strokes.enumerated()), id: \.offset) { _, stroke in
                    Text(stroke.rawValue)
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 18)
                }
            }
        }
    }
}
