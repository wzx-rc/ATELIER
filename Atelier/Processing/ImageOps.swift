import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Photos

/// Premultiplied RGBA8 pixels, top-left origin, tightly packed.
struct RGBABuffer: Sendable {
    var width: Int
    var height: Int
    var pixels: [UInt8]
}

enum ImageOps {
    static let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// Bakes orientation, caps the longest side.
    static func normalized(_ image: UIImage, maxSide: CGFloat = 4096) -> CGImage? {
        let px = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        guard px.width >= 1, px.height >= 1 else { return nil }
        let s = min(1, maxSide / max(px.width, px.height))
        let target = CGSize(width: max(1, (px.width * s).rounded()), height: max(1, (px.height * s).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }.cgImage
    }

    static func makeImage(_ b: RGBABuffer) -> CGImage? {
        let data = Data(b.pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: b.width,
                       height: b.height,
                       bitsPerComponent: 8,
                       bitsPerPixel: 32,
                       bytesPerRow: b.width * 4,
                       space: PaintLayer.colorSpace,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider,
                       decode: nil,
                       shouldInterpolate: false,
                       intent: .defaultIntent)
    }

    /// 8-bit coverage mask of a path (255 = inside), top-left origin.
    static func rasterize(_ path: CGPath, width: Int, height: Int) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: width * height)
        data.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: 1, y: -1)
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.addPath(path)
            ctx.fillPath()
        }
        return data
    }

    /// Unsharp mask, optionally limited to a selection.
    static func sharpen(_ image: CGImage, radius: Double, amount: Double, clip: CGPath?) -> CGImage? {
        let input = CIImage(cgImage: image)
        let filter = CIFilter.unsharpMask()
        filter.inputImage = input
        filter.radius = Float(radius)
        filter.intensity = Float(amount)
        guard let output = filter.outputImage?.cropped(to: input.extent),
              let sharp = ciContext.createCGImage(output, from: input.extent, format: .RGBA8, colorSpace: PaintLayer.colorSpace)
        else { return nil }
        guard let clip else { return sharp }
        let ctx = PaintLayer.makeContext(width: image.width, height: image.height)
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        PaintLayer.draw(image, in: rect, context: ctx)
        ctx.saveGState()
        ctx.addPath(clip)
        ctx.clip()
        ctx.clear(rect)
        PaintLayer.draw(sharp, in: rect, context: ctx)
        ctx.restoreGState()
        return ctx.makeImage()
    }

    static func pngData(_ image: CGImage) -> Data? {
        UIImage(cgImage: image).pngData()
    }

    static func jpegData(_ image: CGImage) -> Data? {
        UIImage(cgImage: image).jpegData(compressionQuality: 0.95)
    }
}

enum PhotoSaver {
    enum SaveError: Error { case denied }

    static func save(_ datas: [Data]) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SaveError.denied }
        try await PHPhotoLibrary.shared().performChanges {
            for d in datas {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: d, options: nil)
            }
        }
    }
}

enum PathBuilder {
    /// Builds a path through points. Smooth points use Catmull-Rom tangents, corner points stay sharp.
    static func path(points: [SelPoint], closed: Bool) -> CGPath {
        let path = CGMutablePath()
        let n = points.count
        guard n > 0 else { return path }
        path.move(to: points[0].p)
        let segments = closed ? n : n - 1
        guard segments > 0 else { return path }
        for i in 0..<segments {
            let a = points[i]
            let b = points[(i + 1) % n]
            if !a.smooth && !b.smooth {
                path.addLine(to: b.p)
                continue
            }
            let prev = closed ? points[(i - 1 + n) % n].p : points[max(i - 1, 0)].p
            let next = closed ? points[(i + 2) % n].p : points[min(i + 2, n - 1)].p
            let c1 = a.smooth ? a.p + (b.p - prev) / 6 : a.p
            let c2 = b.smooth ? b.p - (next - a.p) / 6 : b.p
            path.addCurve(to: b.p, control1: c1, control2: c2)
        }
        if closed { path.closeSubpath() }
        return path
    }

    static func polyline(_ pts: [CGPoint], closed: Bool) -> CGPath {
        let path = CGMutablePath()
        guard let first = pts.first else { return path }
        path.move(to: first)
        if pts.count > 1 { path.addLines(between: pts) }
        if closed { path.closeSubpath() }
        return path
    }
}
