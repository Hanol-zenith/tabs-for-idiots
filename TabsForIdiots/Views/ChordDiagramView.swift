import SwiftUI

struct ChordDiagramView: View {
    let chord: ChordDefinition
    let stringCount: Int

    private let fretCount = 4
    private let cellW: CGFloat = 14
    private let cellH: CGFloat = 14
    private let dotR: CGFloat = 5

    var gridW: CGFloat { cellW * CGFloat(stringCount - 1) }

    var body: some View {
        VStack(spacing: 4) {
            Text(chord.name)
                .font(.system(size: 13, weight: .semibold))

            Canvas { ctx, size in
                let originX = (size.width - gridW) / 2
                let originY: CGFloat = 12

                if chord.baseFret == 1 {
                    let nutRect = CGRect(x: originX, y: originY, width: gridW, height: 3)
                    ctx.fill(Path(nutRect), with: .foreground)
                }

                for f in 0...fretCount {
                    let y = originY + (chord.baseFret == 1 ? 3 : 0) + CGFloat(f) * cellH
                    let line = Path { p in
                        p.move(to: CGPoint(x: originX, y: y))
                        p.addLine(to: CGPoint(x: originX + gridW, y: y))
                    }
                    ctx.stroke(line, with: .foreground, lineWidth: 0.5)
                }

                for s in 0..<stringCount {
                    let x = originX + CGFloat(s) * cellW
                    let topY = originY + (chord.baseFret == 1 ? 3 : 0)
                    let line = Path { p in
                        p.move(to: CGPoint(x: x, y: topY))
                        p.addLine(to: CGPoint(x: x, y: topY + CGFloat(fretCount) * cellH))
                    }
                    ctx.stroke(line, with: .foreground, lineWidth: 0.5)
                }

                for (s, fret) in chord.frets.enumerated() where s < stringCount {
                    let x = originX + CGFloat(s) * cellW
                    let y = originY - 10
                    if fret == 0 {
                        let circle = Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8))
                        ctx.stroke(circle, with: .foreground, lineWidth: 1)
                    } else if fret < 0 {
                        ctx.draw(Text("✕").font(.system(size: 8)), at: CGPoint(x: x, y: y))
                    }
                }

                for (s, fret) in chord.frets.enumerated() where fret > 0 && s < stringCount {
                    let adjustedFret = fret - chord.baseFret + 1
                    guard adjustedFret > 0 && adjustedFret <= fretCount else { continue }
                    let x = originX + CGFloat(s) * cellW
                    let topY = originY + (chord.baseFret == 1 ? 3 : 0)
                    let y = topY + CGFloat(adjustedFret - 1) * cellH + cellH / 2
                    let dot = Path(ellipseIn: CGRect(x: x - dotR, y: y - dotR, width: dotR * 2, height: dotR * 2))
                    ctx.fill(dot, with: .foreground)
                }
            }
            .frame(width: CGFloat(stringCount - 1) * cellW + 20,
                   height: CGFloat(fretCount) * cellH + 30)

            if chord.baseFret > 1 {
                Text("\(chord.baseFret)fr")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
