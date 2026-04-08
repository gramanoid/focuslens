import Foundation
import SwiftUI

enum ActivityCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case coding
    case work
    case writing
    case noteTaking
    case browsing
    case communication
    case ai
    case productivity
    case media
    case design
    case library
    case sleeping
    case other
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .coding: "Coding"
        case .work: "Work"
        case .writing: "Writing"
        case .noteTaking: "Note Taking"
        case .browsing: "Browsing"
        case .communication: "Communication"
        case .ai: "AI"
        case .productivity: "Productivity"
        case .media: "Media"
        case .design: "Design"
        case .library: "Library"
        case .sleeping: "Device Sleeping"
        case .other: "Other"
        case .unknown: "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .coding: Color.blue
        case .work: Color(red: 0.2, green: 0.5, blue: 0.8)
        case .writing: Color.green
        case .noteTaking: Color(red: 0.4, green: 0.7, blue: 0.4)
        case .browsing: Color.orange
        case .communication: Color.pink
        case .ai: Color(red: 0.6, green: 0.4, blue: 0.9)
        case .productivity: Color(red: 0.9, green: 0.7, blue: 0.2)
        case .media: Color.purple
        case .design: Color.teal
        case .library: Color(red: 0.6, green: 0.45, blue: 0.3)
        case .sleeping: Color(red: 0.3, green: 0.3, blue: 0.4)
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
