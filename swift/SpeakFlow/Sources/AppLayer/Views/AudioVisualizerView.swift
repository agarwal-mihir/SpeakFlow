import SwiftUI

/// A modern vertical-bar audio visualizer that reacts to a live audio level.
struct AudioVisualizerView: View {
    let level: Float
    let barCount: Int
    let isActive: Bool

    @State private var barHeights: [CGFloat] = []

    init(level: Float, barCount: Int = 24, isActive: Bool = true) {
        self.level = level
        self.barCount = barCount
        self.isActive = isActive
    }

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor(for: index))
                    .frame(width: 4, height: barHeight(for: index))
            }
        }
        .frame(height: 48)
        .onChange(of: level) { _, newLevel in
            withAnimation(.easeOut(duration: 0.08)) {
                updateBars(level: newLevel)
            }
        }
        .onAppear {
            barHeights = Array(repeating: 4, count: barCount)
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        guard index < barHeights.count else { return 4 }
        return isActive ? barHeights[index] : 4
    }

    private func barColor(for index: Int) -> Color {
        guard isActive else { return .secondary.opacity(0.3) }
        let normalizedHeight = barHeight(for: index) / 48.0
        if normalizedHeight > 0.7 {
            return .red
        } else if normalizedHeight > 0.4 {
            return .orange
        } else {
            return .green
        }
    }

    private func updateBars(level: Float) {
        let clamped = CGFloat(min(max(level, 0), 1))
        var newHeights = [CGFloat]()
        let center = barCount / 2

        for i in 0..<barCount {
            let distFromCenter = abs(CGFloat(i - center)) / CGFloat(center)
            // Bars near center are taller; edges taper off
            let taper = 1.0 - (distFromCenter * 0.6)
            // Add some randomness for organic feel
            let jitter = CGFloat.random(in: 0.7...1.0)
            let height = max(4, clamped * 48 * taper * jitter)
            newHeights.append(height)
        }
        barHeights = newHeights
    }
}
