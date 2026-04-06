# FocusLens — Copilot Instructions

## Design Context

### Users
- Solo power users who want a private, lightweight way to understand how they actually spend their working hours.
- They use FocusLens while already deep in work, so the interface needs to explain state quickly and stay out of the way.
- The main job to be done is to quietly capture activity, confirm the system is trustworthy, and make it easy to review patterns later.

### Brand Personality
- Calm, trustworthy, quietly intelligent, polished.

### Aesthetic Direction
- Dark-first native macOS utility with restrained emerald accents and soft graphite surfaces.
- Feels like a thoughtful instrument panel, not a dashboard toy.
- Reference: **Raycast** — the command palette density, dark surface layering, and restrained use of accent color.
- Anti-references: playful consumer onboarding, neon/loud colors, over-decorated dashboards, gamification.

### Design Principles
1. **Lead with clarity**: every state should explain what is happening and what the next useful action is.
2. **Reduce setup anxiety**: first-run screens should reassure the user about privacy, locality, and what is required.
3. **Reveal complexity progressively**: the menu bar popover guides setup first, then surfaces summary and controls.
4. **Keep visual weight low**: use quiet hierarchy, gentle contrast, and minimal motion.
5. **Make trust visible**: reinforce local-only processing, screenshot handling, and server readiness in the UI.

### Design Tokens
All UI values live in `FocusLens/UI/DesignTokens.swift` via the `DS` enum. Never hard-code radii, opacities, or background colors — always reference `DS.Radius.*`, `DS.Surface.*`, `DS.Background.*`, `DS.Spacing.*`, `DS.Motion.*`.

### Accessibility
- Apple HIG best-effort. Keyboard reachable controls, `accessibilityLabel` on icon-only buttons, Canvas elements need accessible representations, color never the sole information channel, respect `prefers-reduced-motion`.
