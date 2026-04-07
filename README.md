# FocusLens

A native macOS menu bar app that silently captures your screen and keystrokes, classifies your activity with a local vision model, and visualizes your work patterns — all without sending a single byte off your Mac.

## What It Does

FocusLens takes periodic screenshots, records what you type, sends both to a local `llama.cpp` vision server running on your machine, and builds a searchable timeline of what you were working on. Think of it as a private activity journal powered by on-device AI — with three layers of signal for maximum accuracy.

### Three Layers of Tracking

| Layer | What It Captures | How It Helps |
| --- | --- | --- |
| **Screenshots** | Periodic screen captures at configurable intervals | Visual context — what's on screen |
| **OCR + Vision** | Local vision model classifies app, category, and task | Structured activity data |
| **Keystrokes** | Actual characters typed, grouped by app | Ground truth — what you wrote, coded, or sent |

A screenshot of Slack is ambiguous. A screenshot of Slack + "typed 'let's push the deadline to Friday'" gives the model definitive context.

### Features

- **Menu bar app** — lives in your menu bar, no Dock icon, no distractions
- **Local-only AI** — all inference runs on your Mac via `llama-server`
- **Keystroke tracking** — records typed text per-app, injects into classification prompt for richer analysis
- **Auto model management** — pick from 4 recommended models, FocusLens downloads and starts the server for you
- **Activity timeline** — scrollable card-based view with app icons, task descriptions, and confidence scores
- **Insights dashboard** — category breakdown, hourly heatmap, focus score trends, context switch tracking
- **AI analysis** — ask your local model to analyze your productivity patterns with keystroke context
- **CSV / JSON / Markdown export** — get your data out in any format
- **Privacy-first** — screenshots can be auto-deleted, keystrokes stored locally, password fields auto-skipped

## Requirements

- macOS 13.0+
- [llama.cpp](https://github.com/ggerganov/llama.cpp) (`brew install llama.cpp`)
- Xcode or Swift 5.9+ toolchain (to build)

## Quick Start

```bash
# Install dependencies
brew install llama.cpp xcodegen

# Clone and build
git clone https://github.com/gramanoid/focuslens.git
cd focuslens
xcodegen generate
open FocusLens.xcodeproj
```

Or build directly with SwiftPM:

```bash
swift build
```

## First Launch

1. **Grant Screen Recording** — macOS will prompt you, or use the in-app setup flow
2. **Grant Accessibility** (optional) — enables keystroke tracking for richer classification
3. **Select a model** — open Preferences and pick from the recommended models:

| Model | Size | Best For |
| --- | --- | --- |
| **Qwen2-VL 2B** | ~1.7 GB | Lightweight daily use, great OCR |
| Moondream 2 | ~1.7 GB | Fast app detection |
| LLaVA 1.5 7B | ~4 GB | Detailed task descriptions |
| LLaVA 1.6 Mistral 7B | ~4.5 GB | Highest accuracy |

3. **FocusLens downloads the model and starts the server automatically** — no Terminal commands needed
4. **Your first capture happens** within the configured interval (default: 1 minute)

## Architecture

```
FocusLens/
├── App/          # AppState, app lifecycle
├── AI/           # LlamaCppClient, ModelDefinition, ModelDownloadManager, ServerProcessManager
├── Capture/      # Screen capture + keystroke monitoring
├── Storage/      # SQLite via GRDB (sessions, keystrokes, analyses)
├── UI/           # SwiftUI views, design tokens (DS enum)
│   └── ActivityExplorer/
│       ├── TimelineTab/    # Card timeline + Gantt view
│       ├── InsightsTab/    # Charts, heatmap, focus score
│       └── AIAnalysisTab/  # Streaming LLM analysis
└── Utils/        # Image helpers, app icon resolver
```

## Design System

All UI values are centralized in `FocusLens/UI/DesignTokens.swift`:

- **`DS.Radius`** — 4-step corner radius scale (sm/md/lg/xl)
- **`DS.Surface`** — semantic dark-surface opacity hierarchy (inset/card/raised/overlay)
- **`DS.Accent`** — emerald primary (#10B981), warning, caution, processing
- **`DS.Spacing`** — 4pt base grid
- **`DS.Emphasis`** — accent tint opacity scale (subtle/medium/strong)
- **`DS.Motion`** — animation duration tokens with `motionSafe()` modifier for reduced-motion support

## Storage

All data stays local:

- **Database**: `~/Library/Application Support/FocusLens/focuslens.sqlite`
- **Screenshots**: `~/Library/Application Support/FocusLens/screenshots/` (configurable)

Screenshots are saved as `YYYY-MM-DD_HH-mm-ss_AppName.png`.

## Privacy

- All inference runs on localhost via `llama-server` — no cloud APIs
- No telemetry, no analytics, no network calls beyond `localhost`
- Screenshots are optional and can be auto-deleted after classification
- Keystroke data is stored locally in the same SQLite database — never leaves your Mac
- Password fields are automatically skipped (macOS secure input returns nil to global monitors)
- Keystroke tracking is optional and can be toggled off in Preferences
- Communication apps that block screen capture (Telegram, WhatsApp) are detected and handled gracefully

## License

MIT
