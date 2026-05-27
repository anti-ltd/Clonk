import SwiftUI
import iUX_MacOS

// Floating clicks-per-minute readout. Mirror of WPMVisualizerView, fed
// from AppModel.cpmHistory (sampled 4×/sec).
struct CPMVisualizerView: View {
    let model: AppModel

    private var displayCPM: String {
        let v = model.currentCPM
        guard v.isFinite, v >= 0 else { return "0" }
        return String(Int(min(v, 9999)))
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text(displayCPM)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(.white)
                    .frame(minWidth: 60, alignment: .leading)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: displayCPM)
                Text("CPM")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.55))
            }
            MeterSparkline(values: model.cpmHistory, floor: 30)
                .frame(width: 130, height: 44)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassPanel()
    }
}
