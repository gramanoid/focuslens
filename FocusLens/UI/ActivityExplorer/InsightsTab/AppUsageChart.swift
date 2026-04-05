import Charts
import SwiftUI

struct AppUsageChart: View {
    let data: [AppUsageSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App Usage")
                .font(.headline)
            Chart(data) { item in
                BarMark(
                    x: .value("Hours", item.duration / 3600),
                    y: .value("App", item.app)
                )
                .foregroundStyle(item.dominantCategory.color)
            }
            .frame(height: 320)
        }
        .padding(18)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22))
    }
}
