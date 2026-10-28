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
        // Some retailer CDNs already supply a transparent product PNG. Running
        // Vision or the white-background fallback on it can erase pale products
        // (for example a cream tumbler), so preserve the source alpha instead.
        let outputData: Data
        if hasTransparentCanvasCorners(in: inputImage),
           let transparentSource = UIImage(cgImage: inputImage).pngData() {
            outputData = transparentSource
        } else if let studioCutout = makeUniformGrayBackgroundTransparentPNGData(from: inputImage) {
            outputData = studioCutout
        } else {
            outputData = try makeTransparentPNGData(from: inputImage)
        }
        return try writeRemovedImage(trimmedTransparentPNG(outputData), itemID: item.id)
    }

    /// White products on a neutral-gray studio backdrop confuse both Vision's
    /// foreground mask and the white-backdrop fallback. Remove only backdrop
    /// pixels connected to the canvas edge, preserving dark logos inside the
    /// product and the lighter fabric itself.
    private func makeUniformGrayBackgroundTransparentPNGData(from image: CGImage) -> Data? {
        let width = image.width
        let height = image.height
        guard width > 8, height > 8 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let cornerOffsets = [0, width - 1, (height - 1) * width, height * width - 1].map { $0 * 4 }
        let background = (0..<3).map { channel in
            cornerOffsets.map { Int(pixels[$0 + channel]) }.reduce(0, +) / cornerOffsets.count
        }
        let cornerSpread = (0..<3).map { channel in
            let values = cornerOffsets.map { Int(pixels[$0 + channel]) }
            return (values.max() ?? 0) - (values.min() ?? 0)
        }.max() ?? 0
        guard (180...235).contains(background[0]),
              max(background[0], background[1], background[2]) - min(background[0], background[1], background[2]) < 12,
              cornerSpread < 32,
              cornerOffsets.allSatisfy({ pixels[$0 + 3] > 250 }) else { return nil }

        let center = (height / 2 * width + width / 2) * 4
        guard (0..<3).contains(where: { abs(Int(pixels[center + $0]) - background[$0]) > 23 }) else { return nil }

        var visited = [UInt8](repeating: 0, count: width * height)
        var queue: [Int] = []
        queue.reserveCapacity(width * height / 2)
        func enqueue(_ index: Int) {
            guard visited[index] == 0 else { return }
            let pixel = index * 4
            let x = index % width
            let y = index / width
            // Retailer studio backdrops often have a small lighting gradient.
            // Compare with the bilinear backdrop color at this position rather
            // than a single average, so shaded white fabric stays foreground.
            let matchesBackdrop = (0..<3).allSatisfy { channel in
                let top = (Int(pixels[cornerOffsets[0] + channel]) * (width - 1 - x)
                    + Int(pixels[cornerOffsets[1] + channel]) * x) / (width - 1)
                let bottom = (Int(pixels[cornerOffsets[2] + channel]) * (width - 1 - x)
                    + Int(pixels[cornerOffsets[3] + channel]) * x) / (width - 1)
                let expected = (top * (height - 1 - y) + bottom * y) / (height - 1)
                return abs(Int(pixels[pixel + channel]) - expected) <= 12
            }
            guard matchesBackdrop else { return }
            visited[index] = 1
            queue.append(index)
        }
        for x in 0..<width {
            enqueue(x)
            enqueue((height - 1) * width + x)
        }
        for y in 0..<height {
            enqueue(y * width)
            enqueue(y * width + width - 1)
        }
        var cursor = 0
        while cursor < queue.count {
            let index = queue[cursor]
            cursor += 1
            let x = index % width
            let y = index / width
            if x > 0 { enqueue(index - 1) }
            if x + 1 < width { enqueue(index + 1) }
            if y > 0 { enqueue(index - width) }
            if y + 1 < height { enqueue(index + width) }
        }
        guard queue.count > width * height / 10, queue.count < width * height * 9 / 10 else { return nil }
        for index in queue {
            let pixel = index * 4
            pixels[pixel] = 0
            pixels[pixel + 1] = 0
            pixels[pixel + 2] = 0
            pixels[pixel + 3] = 0
        }
        guard let cutout = context.makeImage() else { return nil }
        return UIImage(cgImage: cutout).pngData()
    }

    /// The collage measures the PNG canvas, so trim empty pixels before saving
    /// instead of letting a small object float inside a full-size transparent photo.
    private func trimmedTransparentPNG(_ data: Data) -> Data {
        guard let image = UIImage(data: data)?.cgImage else { return data }
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return data }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 16 {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return data }
        let padding = max(8, min(width, height) / 50)
        let bounds = CGRect(
            x: max(0, minX - padding),
            y: max(0, minY - padding),
            width: min(width - max(0, minX - padding), maxX - minX + 1 + padding * 2),
            height: min(height - max(0, minY - padding), maxY - minY + 1 + padding * 2)
        )
        guard let cropped = image.cropping(to: bounds), let output = UIImage(cgImage: cropped).pngData() else { return data }
        return output
    }

    private func loadImageData(from url: URL) async throws -> Data {
        if url.isFileURL {
            return try Data(contentsOf: url)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw AppError.unavailable("The retailer would not provide that product image.")
        }
        return data
    }

    private func normalizedImage(from data: Data) throws -> CGImage {
        guard let sourceImage = UIImage(data: data),
              sourceImage.cgImage != nil else {
            throw AppError.unavailable("This product image could not be decoded for background removal.")
        }

        let maximumDimension: CGFloat = 2_048
        // UIImage.size includes the image's orientation metadata. Using the raw
        // CGImage dimensions here makes portrait camera captures render into a
        // landscape canvas (or vice versa), which stretches the cutout after
        // Vision removes the background.
        let sourceSize = sourceImage.size
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
              hasTransparentCanvasCorners(in: cgImage),
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
