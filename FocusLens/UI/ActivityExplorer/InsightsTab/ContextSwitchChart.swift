import Charts
import SwiftUI

struct ContextSwitchChart: View {
    let points: [HourlySwitchPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Context Switch Frequency")
                .font(.system(.headline, design: .rounded, weight: .bold))
            Chart(points) { point in
                BarMark(
                    x: .value("Hour", point.hour),
                    y: .value("Switches", point.averageSwitches)
                )
                .foregroundStyle(DS.Accent.warning)
            }
            .frame(height: 180)
        }
        .padding(DS.Spacing.lg)
        .background(DS.Surface.card, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Context switch frequency chart")
    }
}
