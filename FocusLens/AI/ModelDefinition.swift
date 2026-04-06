import Foundation

struct ModelDefinition: Identifiable, Hashable, Codable {
    let id: String
    let displayName: String
    let modelFileName: String
    let mmprojFileName: String
    let modelURL: URL
    let mmprojURL: URL
    let sizeDescription: String
    let qualityDescription: String
    let imageMinTokens: Int
    let description: String
    let pros: [String]
    let cons: [String]

    var modelPath: String {
        (("~/models/" + modelFileName) as NSString).expandingTildeInPath
    }

    var mmprojPath: String {
        (("~/models/" + mmprojFileName) as NSString).expandingTildeInPath
    }

    var isDownloaded: Bool {
        modelFileExists && mmprojFileExists
    }

    var modelFileExists: Bool {
        FileManager.default.fileExists(atPath: modelPath)
    }

    var mmprojFileExists: Bool {
        FileManager.default.fileExists(atPath: mmprojPath)
    }
}

extension ModelDefinition {
    static let recommended: [ModelDefinition] = [
        ModelDefinition(
            id: "qwen2-vl-2b",
            displayName: "Qwen2-VL 2B",
            modelFileName: "Qwen2-VL-2B-Instruct-Q4_K_M.gguf",
            mmprojFileName: "mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf",
            modelURL: URL(string: "https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/Qwen2-VL-2B-Instruct-Q4_K_M.gguf")!,
            mmprojURL: URL(string: "https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf")!,
            sizeDescription: "~1.7 GB",
            qualityDescription: "Best lightweight",
            imageMinTokens: 1024,
            description: "Alibaba's compact vision-language model with strong OCR and screenshot understanding. The recommended default for most users.",
            pros: ["Fastest inference on Apple Silicon", "Excellent OCR and UI text reading", "Small disk and memory footprint"],
            cons: ["May struggle with complex multi-window layouts", "Less accurate on non-English UI"]
        ),
        ModelDefinition(
            id: "moondream2",
            displayName: "Moondream 2",
            modelFileName: "moondream2.gguf",
            mmprojFileName: "moondream2-mmproj-f16.gguf",
            modelURL: URL(string: "https://huggingface.co/ggml-org/moondream2-20250414-GGUF/resolve/main/moondream2-20250414-Q4_K_M.gguf")!,
            mmprojURL: URL(string: "https://huggingface.co/moondream/moondream2-gguf/resolve/main/moondream2-mmproj-f16.gguf")!,
            sizeDescription: "~1.7 GB",
            qualityDescription: "Fast detection",
            imageMinTokens: 0,
            description: "Lightweight model optimized for speed. Good at detecting which app is in use but less detailed in task descriptions.",
            pros: ["Very fast classification", "Low memory usage", "Good app detection accuracy"],
            cons: ["Less detailed task descriptions", "Weaker at reading small UI text", "May misidentify similar-looking apps"]
        ),
        ModelDefinition(
            id: "llava-v1.5-7b",
            displayName: "LLaVA 1.5 7B",
            modelFileName: "llava-v1.5-7b.Q4_K_M.gguf",
            mmprojFileName: "mmproj-model-f16.gguf",
            modelURL: URL(string: "https://huggingface.co/mys/ggml_llava-v1.5-7b/resolve/main/ggml-model-q4_k.gguf")!,
            mmprojURL: URL(string: "https://huggingface.co/mys/ggml_llava-v1.5-7b/resolve/main/mmproj-model-f16.gguf")!,
            sizeDescription: "~4 GB",
            qualityDescription: "Better accuracy",
            imageMinTokens: 0,
            description: "Larger vision model with significantly better scene understanding. Produces richer task descriptions and handles complex layouts well.",
            pros: ["More accurate task descriptions", "Better multi-window understanding", "Handles complex IDE layouts"],
            cons: ["Slower inference (~3-5s per capture)", "Requires 6+ GB RAM for the server", "Larger download"]
        ),
        ModelDefinition(
            id: "llava-v1.6-mistral-7b",
            displayName: "LLaVA 1.6 Mistral 7B",
            modelFileName: "llava-v1.6-mistral-7b.Q4_K_M.gguf",
            mmprojFileName: "llava-v1.6-mistral-mmproj-f16.gguf",
            modelURL: URL(string: "https://huggingface.co/cjpais/llava-1.6-mistral-7b-gguf/resolve/main/llava-v1.6-mistral-7b.Q4_K_M.gguf")!,
            mmprojURL: URL(string: "https://huggingface.co/cjpais/llava-1.6-mistral-7b-gguf/resolve/main/mmproj-model-f16.gguf")!,
            sizeDescription: "~4.5 GB",
            qualityDescription: "Best accuracy",
            imageMinTokens: 0,
            description: "The most capable model available. Built on Mistral 7B with improved visual grounding. Best for users who want the richest analysis.",
            pros: ["Highest accuracy classifications", "Best task description quality", "Strong reasoning about screen context"],
            cons: ["Slowest inference (~5-8s per capture)", "Requires 8+ GB RAM", "Largest download"]
        ),
    ]

    static let custom = ModelDefinition(
        id: "custom",
        displayName: "Custom model path",
        modelFileName: "",
        mmprojFileName: "",
        modelURL: URL(string: "https://huggingface.co")!,
        mmprojURL: URL(string: "https://huggingface.co")!,
        sizeDescription: "User-provided",
        qualityDescription: "User-provided",
        imageMinTokens: 1024,
        description: "Point to your own GGUF model and mmproj files. For advanced users with custom fine-tunes or newer models.",
        pros: ["Full control over model choice"],
        cons: ["No auto-download", "You manage file paths"]
    )

    static var all: [ModelDefinition] {
        recommended + [custom]
    }

    static func find(id: String) -> ModelDefinition? {
        all.first { $0.id == id }
    }

    static func modelsDirectoryURL() -> URL {
        URL(fileURLWithPath: ("~/models" as NSString).expandingTildeInPath)
    }

    static func ensureModelsDirectory() throws {
        try FileManager.default.createDirectory(
            at: modelsDirectoryURL(),
            withIntermediateDirectories: true
        )
    }
}
