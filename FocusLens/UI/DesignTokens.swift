import SwiftUI

// MARK: - Design Tokens

/// Centralized design constants for the FocusLens dark UI.
/// Every surface, radius, and spacing value should come from here
/// so the design language stays coherent as the app grows.
enum DS {

    // MARK: Accent Colors

    enum Accent {
        /// Primary emerald accent — #10B981.
        static let primary = Color(red: 16.0/255, green: 185.0/255, blue: 129.0/255)
        /// Warning state — server down, permission needed.
        static let warning = Color.orange
        /// Caution state — model not connected.
        static let caution = Color.yellow
        /// Processing state — classifying.
        static let processing = Color.teal
    }

    // MARK: Emphasis Opacities

    /// Opacity levels for accent tints on dark surfaces.
    enum Emphasis {
        /// Subtle tint — hero gradients, area fills.
        static let subtle: Double = 0.14
        /// Medium tint — selected chips, category filters.
        static let medium: Double = 0.20
        /// Strong tint — active buttons, selected interval.
        static let strong: Double = 0.24
    }

    // MARK: Corner Radii

    /// 4-step radius scale used throughout the app.
    enum Radius {
        /// Small elements: capsule labels, inner chips — 12pt
        static let sm: CGFloat = 12
        /// Medium elements: metric tiles, inner cards, inputs — 16pt
        static let md: CGFloat = 16
        /// Large elements: cards, chart containers, session cards — 20pt
        static let lg: CGFloat = 20
        /// Extra-large: hero sections, outer cards — 24pt
        static let xl: CGFloat = 24
    }

    // MARK: Surfaces (white-on-dark opacity)

    enum Surface {
        /// Deepest inset surface — subtle background within cards.
        static let inset = Color.white.opacity(0.04)
        /// Standard card/container surface.
        static let card = Color.white.opacity(0.06)
        /// Raised surface for hover states or elevated elements.
        static let raised = Color.white.opacity(0.08)
        /// Highest elevation — tooltips, overlays.
        static let overlay = Color.white.opacity(0.10)
    }

    // MARK: Backgrounds

    enum Background {
        /// Primary window background — dark gradient.
        static let primary = LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.05, blue: 0.06),
                Color(red: 0.02, green: 0.02, blue: 0.03)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        /// Dashboard background — slightly bluer.
        static let dashboard = LinearGradient(
            colors: [Color.black, Color(red: 0.04, green: 0.06, blue: 0.08)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        /// Solid dark for sheets.
        static let sheet = Color(red: 0.04, green: 0.05, blue: 0.06)
    }

    // MARK: Spacing

    /// 4pt base grid spacing scale.
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        /// Compact card spacing — between sm and md.
        static let smMd: CGFloat = 10
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
    }

    // MARK: Animation

    enum Motion {
        /// Default interaction duration.
        static let fast: Double = 0.15
        /// Standard transition.
        static let normal: Double = 0.25
        /// Emphasis transitions.
        static let slow: Double = 0.4

        static let defaultSpring = Animation.spring(response: 0.35, dampingFraction: 0.85)
    }
}

// MARK: - Hover Feedback Modifier

/// Tracks hover state and adjusts background brightness.
struct HoverFeedback: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .brightness(isHovered ? 0.06 : 0)
            .motionSafe(.easeOut(duration: DS.Motion.fast), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

extension View {
    /// Adds subtle hover brightness feedback — appropriate for dark UIs.
    func hoverFeedback() -> some View {
        modifier(HoverFeedback())
    }

    /// Conditionally applies animation only when reduced motion is off.
    func motionSafe(_ animation: Animation, value: some Equatable) -> some View {
        modifier(MotionSafeModifier(animation: animation, value: value))
    }
}

/// Respects the user's Reduce Motion preference by suppressing animations.
private struct MotionSafeModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}
