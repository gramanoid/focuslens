import Charts
import SwiftUI

struct FocusScoreChart: View {
    let points: [FocusScorePoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Focus Score Over Time")
                .font(.headline)
            Chart(points) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Focus", point.score)
                )
                .foregroundStyle(.green)
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("Focus", point.score)
                )
                .foregroundStyle(.green.opacity(0.14))
            }
            .chartYScale(domain: 0 ... 100)
            .frame(height: 260)
        }
        .padding(18)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22))
    }
}
