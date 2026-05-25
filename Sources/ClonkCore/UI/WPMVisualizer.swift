import SwiftUI
import iUX

// Floating WPM readout. Big number + smoothed rolling area chart pulled
// from AppModel.wpmHistory (sampled 4×/sec).
struct WPMVisualizerView: View {
    let model: AppModel

    private var displayWPM: String {
        let v = model.currentWPM
        guard v.isFinite, v >= 0 else { return "0" }
        return String(Int(min(v, 9999)))
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text(displayWPM)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(.white)
                    .frame(minWidth: 60, alignment: .leading)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: displayWPM)
                Text("WPM")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.55))
            }
            MeterSparkline(values: model.wpmHistory)
                .frame(width: 130, height: 44)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassPanel()
    }
}
