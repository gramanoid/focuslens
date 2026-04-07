import SwiftUI

struct GanttView: View {
    let blocks: [SessionBlock]
    let day: Date

    private var rows: [(String, [SessionBlock])] {
        Dictionary(grouping: blocks, by: \.app)
            .map { ($0.key, $0.value.sorted { $0.start < $1.start }) }
            .sorted { $0.0 < $1.0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                ForEach(rows, id: \.0) { row in
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        Text(row.0)
                            .font(.headline)
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: DS.Radius.md)
                                    .fill(DS.Surface.inset)
                                ForEach(row.1, id: \.id) { block in
                                    let frame = frameForBlock(block, width: proxy.size.width)
                                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                                        .fill(block.category.color.gradient)
                                        .frame(width: frame.width, height: 28)
                                        .offset(x: frame.minX, y: 6)
                                        .accessibilityLabel("\(block.app), \(block.task), \(AnalysisAggregator.format(duration: block.duration))")
                                        .help("\(block.app) — \(block.task) — \(AnalysisAggregator.format(duration: block.duration))")
                                }
                            }
                        }
                        .frame(height: 40)
                    }
                }
            }
        }
    }

    private func frameForBlock(_ block: SessionBlock, width: CGFloat) -> CGRect {
        let dayStart = Calendar.current.startOfDay(for: day)
        let total = 24 * 3600.0
        let startOffset = block.start.timeIntervalSince(dayStart)
        let endOffset = block.end.timeIntervalSince(dayStart)
        let x = max(0, width * CGFloat(startOffset / total))
        let w = max(6, width * CGFloat((endOffset - startOffset) / total))
        return CGRect(x: x, y: 0, width: w, height: 28)
    }
}
