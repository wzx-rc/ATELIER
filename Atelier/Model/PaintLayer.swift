import UIKit

/// A raster layer, always the size of the document.
/// Its bitmap context uses a flipped CTM so all drawing is done in
/// top-left-origin document coordinates (like UIKit).
final class PaintLayer: Identifiable {
    let id: UUID
    var name: String
    var isVisible: Bool = true
    var opacity: Double = 1
    let width: Int
    let height: Int
    let context: CGContext

    private(set) var version: Int = 0
    private var cached: CGImage?
    private var thumbCache: (version: Int, image: CGImage)?

    var docRect: CGRect { CGRect(x: 0, y: 0, width: width, height: height) }

    init(id: UUID = UUID(), name: String, width: Int, height: Int) {
        self.id = id
        self.name = name
        self.width = max(1, width)
        self.height = max(1, height)
        self.context = PaintLayer.makeContext(width: self.width, height: self.height)
    }

    static let colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()

    /// Premultiplied RGBA8 context, flipped to top-left origin.
    static func makeContext(width: Int, height: Int) -> CGContext {
        guard let ctx = CGContext(data: nil,
                                  width: max(1, width),
                                  height: max(1, height),
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            fatalError("Impossible de créer un contexte bitmap \(width)x\(height)")
        }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        return ctx
    }

    /// Draws a CGImage into a flipped context at a rect given in top-left coordinates.
    static func draw(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    // MARK: Image cache

    var image: CGImage {
        if let c = cached { return c }
        let img = context.makeImage()!
        cached = img
        return img
    }

    var cachedImageIfAny: CGImage? { cached }

    func markDirty() {
        cached = nil
        version &+= 1
    }

    var thumbnail: CGImage? {
        if let t = thumbCache, t.version == version { return t.image }
        let maxSide: CGFloat = 112
        let s = min(1, maxSide / CGFloat(max(width, height)))
        let tw = max(1, Int(CGFloat(width) * s))
        let th = max(1, Int(CGFloat(height) * s))
        let ctx = PaintLayer.makeContext(width: tw, height: th)
        ctx.interpolationQuality = .medium
        PaintLayer.draw(image, in: CGRect(x: 0, y: 0, width: tw, height: th), context: ctx)
        guard let img = ctx.makeImage() else { return nil }
        thumbCache = (version, img)
        return img
    }

    // MARK: Drawing helpers

    func drawImage(_ img: CGImage, in rect: CGRect) {
        PaintLayer.draw(img, in: rect, context: context)
    }

    /// Replaces the whole content. When `adopt` is true the given image is kept as cache
    /// (only safe for images produced from a context with the same format).
    func replace(with img: CGImage, adopt: Bool = false) {
        context.saveGState()
        context.setBlendMode(.copy)
        context.clear(docRect)
        context.restoreGState()
        drawImage(img, in: docRect)
        version &+= 1
        cached = adopt ? img : nil
    }

    // MARK: Pixel access

    func rgbaBuffer() -> RGBABuffer {
        var out = [UInt8](repeating: 0, count: width * height * 4)
        guard let data = context.data else { return RGBABuffer(width: width, height: height, pixels: out) }
        let src = data.assumingMemoryBound(to: UInt8.self)
        let bpr = context.bytesPerRow
        let rowBytes = width * 4
        let h = height
        out.withUnsafeMutableBufferPointer { dst in
            guard let base = dst.baseAddress else { return }
            for y in 0..<h {
                memcpy(base + y * rowBytes, src + y * bpr, rowBytes)
            }
        }
        return RGBABuffer(width: width, height: height, pixels: out)
    }

    func write(_ buffer: RGBABuffer) {
        guard buffer.width == width, buffer.height == height,
              let img = ImageOps.makeImage(buffer) else { return }
        replace(with: img)
    }

    /// Bounding box of non-transparent pixels.
    func contentBounds() -> CGRect? {
        guard let data = context.data else { return nil }
        let p = data.assumingMemoryBound(to: UInt8.self)
        let bpr = context.bytesPerRow
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = p + y * bpr
            for x in 0..<width where row[x * 4 + 3] > 0 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    func trimmedImage() -> CGImage? {
        guard let b = contentBounds() else { return nil }
        return image.cropping(to: b)
    }
}
