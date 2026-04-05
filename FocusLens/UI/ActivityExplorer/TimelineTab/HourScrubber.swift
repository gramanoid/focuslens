import SwiftUI

struct HourScrubber: View {
    let density: [Int: Double]
    @Binding var selectedHour: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0 ..< 24, id: \.self) { hour in
                Button {
                    selectedHour = hour
                    onSelect(hour)
                } label: {
                    VStack(spacing: 6) {
                        Text(String(format: "%02d", hour))
                            .font(.caption2.monospacedDigit())
                        RoundedRectangle(cornerRadius: 6)
                            .fill(color(for: hour))
                            .frame(height: 28)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func color(for hour: Int) -> Color {
        let value = min(1, density[hour] ?? 0)
        if selectedHour == hour {
            return .white
        }
        if value == 0 {
            return .gray.opacity(0.2)
        }
        return .green.opacity(0.25 + value * 0.65)
    }
}
