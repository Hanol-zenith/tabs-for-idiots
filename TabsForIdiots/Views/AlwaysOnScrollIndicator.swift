import SwiftUI

// Drop-in replacement for ScrollView with a permanently-visible custom indicator.
// Native .scrollIndicators(.visible) fades after idle — this never does.
//
// Two design choices that matter:
//  1. No outer GeometryReader — using one as the root would collapse child heights
//     inside a vertical ScrollView (GeometryReader is greedy; it fills all space).
//     Instead, an overlay GeometryReader measures the container without affecting layout.
//  2. Dictionary-keyed preference — nested PersistentScrollViews share the same
//     preference type. Keying by the instance's unique spaceID stops outer instances
//     from consuming inner instances' values.
struct PersistentScrollView<Content: View>: View {
    let axes: Axis.Set
    @ViewBuilder let content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var contentLength: CGFloat = 0
    // UUID baked at first render; stable across re-renders so the coordinate space
    // name and preference key never change for the lifetime of this instance.
    @State private var spaceID = UUID().uuidString

    init(axes: Axis.Set = .vertical, @ViewBuilder content: @escaping () -> Content) {
        self.axes = axes
        self.content = content
    }

    var body: some View {
        ScrollView(axes) {
            content()
                .background(
                    GeometryReader { inner in
                        Color.clear.preference(
                            key: _TrackDict.self,
                            value: [spaceID: _TrackDict.Info(
                                offset: axes == .horizontal
                                    ? -inner.frame(in: .named(spaceID)).minX
                                    : -inner.frame(in: .named(spaceID)).minY,
                                length: axes == .horizontal
                                    ? inner.size.width
                                    : inner.size.height
                            )]
                        )
                    }
                )
        }
        .coordinateSpace(name: spaceID)
        .scrollIndicators(.hidden)
        .onPreferenceChange(_TrackDict.self) { dict in
            if let v = dict[spaceID] {
                offset = v.offset
                contentLength = v.length
            }
        }
        .overlay {
            GeometryReader { proxy in
                let containerLen = axes == .horizontal ? proxy.size.width : proxy.size.height
                trackView(containerLen: containerLen)
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func trackView(containerLen: CGFloat) -> some View {
        if containerLen > 0, contentLength > containerLen {
            let ratio    = containerLen / contentLength
            let thumbLen = max(30, containerLen * ratio)
            let maxScroll = contentLength - containerLen
            let raw      = maxScroll > 0 ? (offset / maxScroll) * (containerLen - thumbLen) : 0
            let pos      = max(0, min(raw, containerLen - thumbLen))

            ZStack(alignment: axes == .horizontal ? .leading : .top) {
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(
                        width:  axes == .horizontal ? containerLen : 3,
                        height: axes == .horizontal ? 3 : containerLen
                    )
                Capsule()
                    .fill(Color.secondary.opacity(0.45))
                    .frame(
                        width:  axes == .horizontal ? thumbLen : 3,
                        height: axes == .horizontal ? 3 : thumbLen
                    )
                    .offset(x: axes == .horizontal ? pos : 0,
                            y: axes == .horizontal ? 0   : pos)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: axes == .horizontal ? .bottom : .trailing)
            .padding(axes == .horizontal ? .bottom : .trailing, 2)
        }
    }
}

private struct _TrackDict: PreferenceKey {
    struct Info: Equatable { var offset: CGFloat = 0; var length: CGFloat = 0 }
    static let defaultValue: [String: Info] = [:]
    static func reduce(value: inout [String: Info], nextValue: () -> [String: Info]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
