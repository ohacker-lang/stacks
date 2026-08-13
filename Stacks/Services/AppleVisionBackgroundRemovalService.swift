import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import UIKit
import Vision

actor AppleVisionBackgroundRemovalService: BackgroundRemovalService {
    func removeBackground(for item: StackItem) async throws -> URL? {
        guard let imageURL = item.originalImageURL else {
            return item.removedBackgroundImageURL
        }

        let imageData = try await loadImageData(from: imageURL)
        let inputImage = try normalizedImage(from: imageData)
        let outputData = try makeTransparentPNGData(from: inputImage)
        return try writeRemovedImage(outputData, itemID: item.id)
    }

    private func loadImageData(from url: URL) async throws -> Data {
        if url.isFileURL {
            return try Data(contentsOf: url)
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }

    private func normalizedImage(from data: Data) throws -> CGImage {
        guard let sourceImage = UIImage(data: data),
              let sourceCGImage = sourceImage.cgImage else {
            throw AppError.unavailable("This product image could not be decoded for background removal.")
        }

        let maximumDimension: CGFloat = 2_048
        let sourceSize = CGSize(width: sourceCGImage.width, height: sourceCGImage.height)
        let scale = min(1, maximumDimension / max(sourceSize.width, sourceSize.height))
        let targetSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let normalized = renderer.image { _ in
            sourceImage.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let normalizedCGImage = normalized.cgImage else {
            throw AppError.unavailable("This product image could not be prepared for background removal.")
        }
        return normalizedCGImage
    }

    private func makeTransparentPNGData(from inputCGImage: CGImage) throws -> Data {
        do {
            return try makeVisionTransparentPNGData(from: inputCGImage)
        } catch {
            // Product imports deliberately favor clean studio imagery; this keeps those images usable
            // when Vision cannot identify an instance on a particular device or source image.
            return try makeWhiteBackgroundTransparentPNGData(from: inputCGImage)
        }
    }

    private func makeVisionTransparentPNGData(from inputCGImage: CGImage) throws -> Data {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: inputCGImage)
        try handler.perform([request])

        guard let result = request.results?.first, !result.allInstances.isEmpty else {
            throw AppError.unavailable("We could not isolate the product from this image.")
        }

        let maskBuffer = try result.generateScaledMaskForImage(
            forInstances: result.allInstances,
            from: handler
        )
        let inputImage = CIImage(cgImage: inputCGImage)
        let maskImage = CIImage(cvPixelBuffer: maskBuffer)
        let clearBackground = CIImage(color: CIColor.clear).cropped(to: inputImage.extent)

        let filter = CIFilter.blendWithMask()
        filter.inputImage = inputImage
        filter.backgroundImage = clearBackground
        filter.maskImage = maskImage

        guard let outputImage = filter.outputImage else {
            throw AppError.notFound
        }

        let context = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
        guard let cgImage = context.createCGImage(outputImage, from: inputImage.extent) else {
            throw AppError.notFound
        }

        // On Simulator and on a few retailer images, Vision can report the entire
        // canvas as foreground. Treat that as a failed mask so the studio-background
        // fallback gets a chance to create a real cutout instead of silently saving
        // an opaque PNG that looks identical to the source.
        guard hasTransparentCanvasCorners(in: cgImage) else {
            throw AppError.unavailable("The foreground mask included the full image.")
        }

        guard let data = UIImage(cgImage: cgImage).pngData(), !data.isEmpty else {
            throw AppError.unavailable("We could not save the isolated product image.")
        }
        return data
    }

    private func makeWhiteBackgroundTransparentPNGData(from inputCGImage: CGImage) throws -> Data {
        let inputImage = CIImage(cgImage: inputCGImage)
        let cubeDimension = 64
        let cubeData = whiteBackgroundCubeData(dimension: cubeDimension)
        let filter = CIFilter.colorCube()
        filter.inputImage = inputImage
        filter.cubeDimension = Float(cubeDimension)
        filter.cubeData = cubeData

        guard let outputImage = filter.outputImage else {
            throw AppError.unavailable("We could not remove the background from this product image.")
        }

        let context = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
        guard let cgImage = context.createCGImage(outputImage, from: inputImage.extent),
              let data = UIImage(cgImage: cgImage).pngData(), !data.isEmpty else {
            throw AppError.unavailable("We could not save the background-removed product image.")
        }
        return data
    }

    private func whiteBackgroundCubeData(dimension: Int) -> Data {
        var values = [Float]()
        values.reserveCapacity(dimension * dimension * dimension * 4)

        for blue in 0..<dimension {
            for green in 0..<dimension {
                for red in 0..<dimension {
                    let r = Float(red) / Float(dimension - 1)
                    let g = Float(green) / Float(dimension - 1)
                    let b = Float(blue) / Float(dimension - 1)
                    let brightness = min(r, min(g, b))
                    let chroma = max(r, max(g, b)) - brightness
                    // Retailers commonly shoot on cool gray (#E5E9EB) rather than
                    // literal white. Product colors and shadows survive because this
                    // only targets bright, low-chroma canvas pixels.
                    let whiteness = chroma < 0.14 ? smoothstep(0.70, 0.88, brightness) : 0
                    let alpha = 1 - whiteness
                    values += [r * alpha, g * alpha, b * alpha, alpha]
                }
            }
        }
        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private func smoothstep(_ lower: Float, _ upper: Float, _ value: Float) -> Float {
        let normalized = min(max((value - lower) / (upper - lower), 0), 1)
        return normalized * normalized * (3 - 2 * normalized)
    }

    private func hasTransparentCanvasCorners(in image: CGImage) -> Bool {
        let width = image.width
        let height = image.height
        guard width > 2, height > 2 else { return false }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let insetX = max(width / 20, 1)
        let insetY = max(height / 20, 1)
        let points = [
            (insetX, insetY),
            (width - insetX - 1, insetY),
            (insetX, height - insetY - 1),
            (width - insetX - 1, height - insetY - 1)
        ]
        let transparentCorners = points.filter { x, y in
            pixels[((y * width) + x) * 4 + 3] < 32
        }
        return transparentCorners.count >= 2
    }

    private func writeRemovedImage(_ data: Data, itemID: UUID) throws -> URL {
        guard !data.isEmpty else { throw AppError.missingRequiredField("Image") }

        // Do not leave finished cutouts in Caches. Caches may be purged at any
        // point, which made previously saved stickers turn back into blanks.
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("Stacks/RemovedBackgrounds", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent("\(itemID.uuidString).png")
        try data.write(to: url, options: [.atomic])
        return url
    }
}
