import CoreGraphics
import Foundation
import ImageIO

/// Pure-Swift perceptual hash (pHash) for screenshot deduplication.
/// Produces a 64-bit hash from image data; near-identical images yield similar hashes.
enum PerceptualHash {
    private static let hashSize = 8
    private static let resizeSize = 32

    /// Compute a 64-bit perceptual hash from PNG/image data.
    /// Returns nil if the data cannot be decoded into a CGImage.
    static func hash(from imageData: Data) -> UInt64? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return hash(from: cgImage)
    }

    /// Compute a 64-bit perceptual hash from a CGImage.
    static func hash(from image: CGImage) -> UInt64? {
        guard let pixels = grayscalePixels(from: image, size: resizeSize) else { return nil }

        // Apply DCT and keep top-left 8x8 coefficients
        let dctCoeffs = dct8x8(from: pixels, inputSize: resizeSize)

        // Exclude DC coefficient (index 0), compute median of remaining 63
        let acCoeffs = Array(dctCoeffs.dropFirst())
        let sorted = acCoeffs.sorted()
        let median = sorted[sorted.count / 2]

        // Build 64-bit hash: bit 0 is DC (always 0), bits 1-63 are AC comparisons
        var hashValue: UInt64 = 0
        for i in 0 ..< 64 {
            if dctCoeffs[i] > median {
                hashValue |= (1 << i)
            }
        }
        return hashValue
    }

    /// Hamming distance between two 64-bit hashes.
    /// 0 = identical, 64 = completely different.
    static func distance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    // MARK: - Private

    /// Resize image to NxN grayscale and extract luminance values as [Double].
    private static func grayscalePixels(from image: CGImage, size: Int) -> [Double]? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: size * size)
        guard let context = CGContext(
            data: &pixels,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        return pixels.map { Double($0) }
    }

    /// Compute the top-left 8x8 DCT-II coefficients from an NxN input.
    /// Returns 64 values in row-major order.
    private static func dct8x8(from pixels: [Double], inputSize n: Int) -> [Double] {
        let h = hashSize
        var result = [Double](repeating: 0, count: h * h)

        // Precompute cosine table
        let piOverN = Double.pi / Double(n)
        var cosTable = [Double](repeating: 0, count: h * n)
        for u in 0 ..< h {
            for i in 0 ..< n {
                cosTable[u * n + i] = cos(piOverN * (Double(i) + 0.5) * Double(u))
            }
        }

        // 2D DCT-II: only compute (u, v) for u in [0, 8), v in [0, 8)
        for u in 0 ..< h {
            for v in 0 ..< h {
                var sum = 0.0
                for x in 0 ..< n {
                    let cosU = cosTable[u * n + x]
                    for y in 0 ..< n {
                        sum += pixels[x * n + y] * cosU * cosTable[v * n + y]
                    }
                }
                result[u * h + v] = sum
            }
        }
        return result
    }
}
