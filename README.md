# FocusLens

FocusLens is a native macOS menu bar app that captures the current screen on a configurable interval, classifies the user’s activity with a local `llama.cpp` vision server, stores the results in SQLite via GRDB, and visualizes the history in a native Activity Explorer dashboard.

## Features

- Menu bar app with no Dock icon
- Configurable silent screen capture using `CGWindowListCreateImage`
- Local-only vision classification through `llama-server`
- SQLite storage with GRDB
- Dashboard with Timeline, Insights, and AI Analysis tabs
- CSV, JSON, and Markdown export
- Optional screenshot deletion after classification
- Launch at login, excluded apps, and server health checks

## Requirements

- macOS 13.0+
- Swift 5.9+ / Swift 6 toolchain works
- XcodeGen for regenerating the Xcode project
- `llama.cpp` installed locally

## Install

```bash
brew install llama.cpp xcodegen
cd /Users/alexgrama/Developer/focuslens
xcodegen generate
open FocusLens.xcodeproj
```

The package also builds directly with SwiftPM:

```bash
swift build
```

## Vision Models

Recommended models for FocusLens:

| Model | Size | Quality |
| --- | --- | --- |
| Qwen2-VL-2B-Instruct Q4_K_M | ~1.0GB + 0.7GB mmproj | Best lightweight screenshot/OCR balance |
| moondream2 | ~1.7GB | Fast, good for app detection |
| llava-v1.5-7b | ~4GB | Better accuracy |
| llava-v1.6-mistral-7b | ~4.5GB | Best accuracy |

Suggested Hugging Face sources:

- `Qwen2-VL-2B-Instruct` GGUF: [ggml-org/Qwen2-VL-2B-Instruct-GGUF](https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF)
- `Qwen2-VL-2B-Instruct` base model card: [Qwen/Qwen2-VL-2B-Instruct](https://huggingface.co/Qwen/Qwen2-VL-2B-Instruct)
- `moondream2` GGUF: [ggml-org/moondream2-20250414-GGUF](https://huggingface.co/ggml-org/moondream2-20250414-GGUF)
- `moondream2` mmproj: [moondream/moondream2-gguf](https://huggingface.co/moondream/moondream2-gguf/blob/main/moondream2-mmproj-f16.gguf)
- `llava-v1.5-7b` GGUF: [mys/ggml_llava-v1.5-7b](https://huggingface.co/mys/ggml_llava-v1.5-7b)
- `llava-v1.5-7b` mmproj: [mys/ggml_llava-v1.5-7b mmproj-model-f16.gguf](https://huggingface.co/mys/ggml_llava-v1.5-7b/blob/main/mmproj-model-f16.gguf)
- `llava-v1.6-mistral-7b` GGUF: [cjpais/llava-1.6-mistral-7b-gguf](https://huggingface.co/cjpais/llava-1.6-mistral-7b-gguf)
- `llava-v1.6-mistral-7b` mmproj: [cjpais/llava-1.6-mistral-7b-gguf mmproj-model-f16.gguf](https://huggingface.co/cjpais/llava-1.6-mistral-7b-gguf/tree/main)

## Start `llama-server`

FocusLens expects an OpenAI-compatible server at `http://localhost:8080`.

Recommended lightweight setup with Qwen2-VL-2B:

```bash
llama-server -m ~/models/Qwen2-VL-2B-Instruct-Q4_K_M.gguf --mmproj ~/models/mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf --port 8080 -ngl 99
```

Vision mode with moondream2:

```bash
llama-server -m ~/models/moondream2.gguf --mmproj ~/models/moondream2-mmproj.gguf --port 8080 -ngl 99
```

Vision mode with LLaVA 1.5:

```bash
llama-server -m ~/models/llava-v1.5-7b.Q4_K_M.gguf --mmproj ~/models/mmproj-model-f16.gguf --port 8080 -ngl 99
```

Vision mode with LLaVA 1.6 Mistral:

```bash
llama-server -m ~/models/llava-v1.6-mistral-7b.Q4_K_M.gguf --mmproj ~/models/mmproj-model-f16.gguf --port 8080 -ngl 99
```

Text-only analysis mode:

```bash
llama-server -m ~/models/moondream2.gguf --mmproj ~/models/moondream2-mmproj.gguf --port 8080 -ngl 99
```

FocusLens uses the same server for both image classification and text-only analysis. When the app sends a text-only analysis request, it simply omits the image content from the request body.

## Grant Screen Recording Permission

On first launch, macOS will ask for Screen Recording access. If it does not:

1. Open **System Settings**
2. Go to **Privacy & Security**
3. Open **Screen Recording**
4. Enable **FocusLens**
5. Relaunch the app

The app also exposes an **Open Privacy Settings** shortcut from its onboarding sheet.

## Storage

FocusLens stores data locally only:

- Database: `~/Library/Application Support/FocusLens/focuslens.sqlite`
- Screenshots: `~/Library/Application Support/FocusLens/screenshots/*.png`

SQLite tables:

- `sessions(id, timestamp, app, bundle_id, category, task, confidence, screenshot_path, raw_response)`
- `analyses(id, timestamp, type, date_range_start, date_range_end, prompt, response)`

## Project Structure

```text
FocusLens/
├── App/
├── Capture/
├── AI/
├── Storage/
├── UI/
└── Utils/
```

## Verification

Verified locally in this workspace with:

```bash
swift build
swift run FocusLens --self-check
```

The `.xcodeproj` is generated and present at `FocusLens.xcodeproj`. `xcodebuild` was not run in this environment because the full Xcode app was not installed; only Command Line Tools were available.
