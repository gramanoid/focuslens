import Charts
import SwiftUI

struct ContextSwitchChart: View {
    let points: [HourlySwitchPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Context Switch Frequency")
                .font(.headline)
            Chart(points) { point in
                BarMark(
                    x: .value("Hour", point.hour),
                    y: .value("Switches", point.averageSwitches)
                )
                .foregroundStyle(.orange)
            }
            .frame(height: 260)
        }
        .padding(18)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22))
    }
}
