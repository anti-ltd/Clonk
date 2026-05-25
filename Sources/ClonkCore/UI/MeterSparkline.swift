import SwiftUI

// Smoothed rolling area chart shared by the WPM / CPM floating readouts.
// Catmull-Rom curve through a fixed-length history with a pulsing head dot.
struct MeterSparkline: View {
    let values: [Double]
    // Vertical-scale floor so a quiet stretch doesn't blow small values
    // up into a full-height spike.
    var floor: Double = 40

    private var peak: Double {
        max(values.max() ?? 1, floor)
    }

    private var currentValue: Double { values.last ?? 0 }

    var body: some View {
        GeometryReader { geo in
            // Inset the drawable area so glow + pulse never touch the edge.
            let inset: CGFloat = 8
            let drawSize = CGSize(
                width: max(geo.size.width - inset * 2, 1),
                height: max(geo.size.height - inset * 2, 1)
            )
            let points = makePoints(in: drawSize)

            ZStack(alignment: .bottomLeading) {
                fillPath(points: points, in: drawSize)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.55),
                                Color.accentColor.opacity(0.0),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                linePath(points: points)
                    .stroke(Color.accentColor.opacity(0.5),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .blur(radius: 3)

                linePath(points: points)
                    .stroke(
                        LinearGradient(
                            colors: [Color.accentColor, .white.opacity(0.9)],
                            startPoint: .bottomLeading,
                            endPoint: .topTrailing
                        ),
                        style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                    )

                if let head = points.last {
                    PulsingDot()
                        .position(head)
                }
            }
            .frame(width: drawSize.width, height: drawSize.height)
            .offset(x: inset, y: inset)
            .animation(.linear(duration: 0.25), value: values)
        }
    }

    private func makePoints(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let step = size.width / Double(values.count - 1)
        let p = peak
        return values.enumerated().map { i, v in
            let x = Double(i) * step
            let norm = min(max(v / p, 0), 1)
            let y = size.height * (1 - norm)
            return CGPoint(x: x, y: y)
        }
    }

    // Catmull-Rom smoothed line through the sampled points.
    private func linePath(points: [CGPoint]) -> Path {
        Path { path in
            guard points.count > 1 else { return }
            path.move(to: points[0])
            for i in 0..<points.count - 1 {
                let p0 = points[max(i - 1, 0)]
                let p1 = points[i]
                let p2 = points[i + 1]
                let p3 = points[min(i + 2, points.count - 1)]
                let cp1 = CGPoint(
                    x: p1.x + (p2.x - p0.x) / 6,
                    y: p1.y + (p2.y - p0.y) / 6
                )
                let cp2 = CGPoint(
                    x: p2.x - (p3.x - p1.x) / 6,
                    y: p2.y - (p3.y - p1.y) / 6
                )
                path.addCurve(to: p2, control1: cp1, control2: cp2)
            }
        }
    }

    private func fillPath(points: [CGPoint], in size: CGSize) -> Path {
        var path = linePath(points: points)
        guard let first = points.first, let last = points.last else { return path }
        path.addLine(to: CGPoint(x: last.x, y: size.height))
        path.addLine(to: CGPoint(x: first.x, y: size.height))
        path.closeSubpath()
        return path
    }
}

private struct PulsingDot: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.45))
                .frame(width: pulse ? 16 : 6, height: pulse ? 16 : 6)
                .opacity(pulse ? 0 : 0.9)
            Circle()
                .fill(Color.white)
                .frame(width: 4, height: 4)
                .shadow(color: Color.accentColor, radius: 4)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}
