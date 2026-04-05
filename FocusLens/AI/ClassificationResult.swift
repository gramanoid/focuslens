import Foundation
import SwiftUI

enum ActivityCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case coding
    case writing
    case browsing
    case communication
    case media
    case design
    case other
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .coding: "Coding"
        case .writing: "Writing"
        case .browsing: "Browsing"
        case .communication: "Communication"
        case .media: "Media"
        case .design: "Design"
        case .other: "Other"
        case .unknown: "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .coding: Color.blue
        case .writing: Color.green
        case .browsing: Color.orange
        case .communication: Color.pink
        case .media: Color.purple
        case .design: Color.teal
        case .other: Color.gray
        case .unknown: Color.secondary
        }
    }

    var chartColor: NSColor {
        NSColor(color)
    }
}

struct ClassificationResult: Codable, Hashable {
    var app: String
    var category: ActivityCategory
    var task: String
    var confidence: Double
    var rawResponse: String?

    static func unknown(from rawResponse: String?) -> ClassificationResult {
        ClassificationResult(
            app: "Unknown",
            category: .unknown,
            task: "FocusLens could not parse the model response.",
            confidence: 0,
            rawResponse: rawResponse
        )
    }
}
