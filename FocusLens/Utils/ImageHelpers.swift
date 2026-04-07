import AppKit
import Foundation

enum ImageHelpers {
    static func applicationSupportDirectory() throws -> URL {
        let baseDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return baseDirectory.appendingPathComponent("FocusLens", isDirectory: true)
    }

    static func screenshotsDirectory(customPath: String? = nil) throws -> URL {
        let directory: URL
        if let customPath, !customPath.isEmpty {
            directory = URL(fileURLWithPath: (customPath as NSString).expandingTildeInPath)
        } else {
            directory = try applicationSupportDirectory().appendingPathComponent("screenshots", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        return directory
    }

    static func pngData(from cgImage: CGImage) -> Data? {
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .png, properties: [:])
    }

    // Desktop screenshots contain small UI text, so OCR quality drops sharply at tiny sizes.
    static func resizedPNGData(from cgImage: CGImage, maxDimension: CGFloat = 1024) -> Data? {
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let scale = min(1, maxDimension / max(width, height))
        guard scale < 0.999 else {
            return pngData(from: cgImage)
        }

        let newSize = CGSize(width: max(1, floor(width * scale)), height: max(1, floor(height * scale)))
        guard let context = CGContext(
            data: nil,
            width: Int(newSize.width),
            height: Int(newSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(origin: .zero, size: newSize))
        guard let resizedImage = context.makeImage() else { return nil }
        return pngData(from: resizedImage)
    }

    static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        try data.write(to: url, options: .atomic)
    }

    static func image(from path: String?) -> NSImage? {
        guard let path else { return nil }
        return NSImage(contentsOfFile: path)
    }

    /// Returns true if the image is predominantly black/blank (> 95% near-black pixels).
    /// Communication apps like Telegram and WhatsApp often render as solid black
    /// due to macOS window sharing restrictions.
    static func isBlankCapture(_ cgImage: CGImage, threshold: Double = 0.98) -> Bool {
        let sampleSize = 64
        guard let context = CGContext(
            data: nil,
            width: sampleSize,
            height: sampleSize,
            bitsPerComponent: 8,
            bytesPerRow: sampleSize * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))
        guard let data = context.data else { return false }

        let pixels = data.assumingMemoryBound(to: UInt8.self)
        let totalPixels = sampleSize * sampleSize
        var darkPixels = 0
        for i in 0..<totalPixels {
            let offset = i * 4
            let brightness = Int(pixels[offset]) + Int(pixels[offset + 1]) + Int(pixels[offset + 2])
            if brightness < 30 { darkPixels += 1 }
        }
        return Double(darkPixels) / Double(totalPixels) > threshold
    }
}
