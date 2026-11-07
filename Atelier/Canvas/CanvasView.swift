import UIKit
import SwiftUI
import Combine

enum CropHandle {
    case none, inside, top, bottom, left, right, topLeft, topRight, bottomLeft, bottomRight
}

/// UIKit canvas: zoom / pan, layer display and all direct-manipulation tools.
final class CanvasView: UIView, UIGestureRecognizerDelegate, UIPencilInteractionDelegate {
    let model: EditorModel

    private let contentView = UIView()
    private let checkerView = UIView()
    let overlay = CanvasOverlayView()

    private var sublayerMap: [UUID: CALayer] = [:]
    private var shownImages: [UUID: CGImage] = [:]
    private let strokeLayer = CALayer()
    private let strokeMask = CAShapeLayer()
    private var strokeContext: CGContext?
    private var strokeDirty = false
    private var directDirty = false
    private var needsSyncFlag = true
    private var displayLink: CADisplayLink?
    private var cancellables = Set<AnyCancellable>()

    private(set) var scale: CGFloat = 1
    private(set) var offset: CGPoint = .zero
    private var docSize: CGSize = .zero
    private var lastBoundsSize: CGSize = .zero
    private(set) var hoverPoint: CGPoint?

    var docToView: CGAffineTransform {
        CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: offset.x, ty: offset.y)
    }

    // Interaction state
    private enum Mode { case none, brush, eraser, eyedrop, shapeSelect, lasso, pointDrag, move, crop, pan }
    private var mode: Mode = .none
    private var activeTouch: UITouch?
    private var startDoc: CGPoint = .zero
    private var startView: CGPoint = .zero
    private var lastView: CGPoint = .zero
    private var lassoPoints: [CGPoint] = []
    private var dragIndex = 0
    private var dragMoved = false
    private var dragIsNew = false
    private var moveOffset: CGPoint = .zero
    private var cropHandle: CropHandle = .none
    private var cropStart: CGRect = .zero
    private var directLayer: PaintLayer?
    private var strokeSettings = BrushSettings()
    private var strokeColor: CGColor = UIColor.white.cgColor
    private var strokeGradient: CGGradient?
    private var lastStamp: CGPoint?
    private var lastPressure: CGFloat = 1
    private var spacingLeft: CGFloat = 0

    private static let noActions: [String: CAAction] = [
        "contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "opacity": NSNull(),
        "hidden": NSNull(), "transform": NSNull(), "sublayers": NSNull(), "mask": NSNull(),
        "magnificationFilter": NSNull(), "path": NSNull(), "frame": NSNull()
    ]

    // MARK: - Init

    init(model: EditorModel) {
        self.model = model
        super.init(frame: .zero)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        clipsToBounds = true

        checkerView.backgroundColor = UIColor(patternImage: CanvasView.checkerTile())
        checkerView.isUserInteractionEnabled = false
        checkerView.layer.shadowColor = UIColor.black.cgColor
        checkerView.layer.shadowOpacity = 0.55
        checkerView.layer.shadowRadius = 22
        checkerView.layer.shadowOffset = CGSize(width: 0, height: 8)
        addSubview(checkerView)

        contentView.isUserInteractionEnabled = false
        contentView.layer.anchorPoint = .zero
        contentView.backgroundColor = .clear
        addSubview(contentView)

        overlay.canvas = self
        addSubview(overlay)

        strokeLayer.anchorPoint = .zero
        strokeLayer.actions = CanvasView.noActions
        strokeMask.actions = CanvasView.noActions
        strokeMask.fillColor = UIColor.white.cgColor

        setupGestures()
        let pencil = UIPencilInteraction()
        pencil.delegate = self
        addInteraction(pencil)

        model.objectWillChange
            .sink { [weak self] _ in self?.needsSyncFlag = true }
            .store(in: &cancellables)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func checkerTile() -> UIImage {
        let s: CGFloat = 10
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(size: CGSize(width: s * 2, height: s * 2), format: format).image { ctx in
            UIColor(white: 0.40, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: s * 2, height: s * 2))
            UIColor(white: 0.50, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
            ctx.fill(CGRect(x: s, y: s, width: s, height: s))
        }
    }

    // MARK: - Display link

    private final class LinkProxy: NSObject {
        weak var target: CanvasView?
        init(_ t: CanvasView) { target = t }
        @objc func tick() { target?.tick() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            if displayLink == nil {
                let link = CADisplayLink(target: LinkProxy(self), selector: #selector(LinkProxy.tick))
                link.add(to: .main, forMode: .common)
                displayLink = link
            }
        } else {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    func setNeedsSync() { needsSyncFlag = true }

    fileprivate func tick() {
        guard strokeDirty || directDirty || needsSyncFlag else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if strokeDirty, let ctx = strokeContext {
            strokeLayer.contents = ctx.makeImage()
            strokeDirty = false
        }
        if directDirty, let l = directLayer {
            let img = l.image
            sublayerMap[l.id]?.contents = img
            shownImages[l.id] = img
            directDirty = false
        }
        if needsSyncFlag {
            needsSyncFlag = false
            sync()
        }
        CATransaction.commit()
    }

    private func forceSync() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        needsSyncFlag = false
        sync()
        CATransaction.commit()
    }

    // MARK: - Sync with model

    private func sync() {
        let newSize = CGSize(width: model.docWidth, height: model.docHeight)
        if newSize != docSize {
            docSize = newSize
            contentView.bounds = CGRect(origin: .zero, size: newSize)
            strokeContext = nil
            fitToScreen()
        }
        strokeLayer.bounds = CGRect(origin: .zero, size: docSize)
        strokeLayer.position = .zero
        strokeMask.frame = CGRect(origin: .zero, size: docSize)

        let activeID = model.activeLayer?.id
        let nearest = scale >= 2.5
        var live = Set<UUID>()
        var ordered: [CALayer] = []
        for l in model.layers {
            live.insert(l.id)
            let cal: CALayer
            if let existing = sublayerMap[l.id] {
                cal = existing
            } else {
                cal = CALayer()
                cal.anchorPoint = .zero
                cal.actions = CanvasView.noActions
                cal.minificationFilter = .trilinear
                cal.contentsGravity = .resize
                sublayerMap[l.id] = cal
            }
            cal.bounds = CGRect(x: 0, y: 0, width: l.width, height: l.height)
            cal.position = (mode == .move && l.id == activeID) ? moveOffset : .zero
            var desired = l.image
            if let p = model.preview, p.layerID == l.id { desired = p.image }
            if shownImages[l.id] !== desired {
                cal.contents = desired
                shownImages[l.id] = desired
            }
            cal.opacity = Float(l.opacity)
            cal.isHidden = !l.isVisible
            cal.magnificationFilter = nearest ? .nearest : .linear
            ordered.append(cal)
            if l.id == activeID {
                strokeLayer.opacity = Float(strokeSettings.opacity)
                strokeLayer.isHidden = !l.isVisible
                ordered.append(strokeLayer)
            }
        }
        for id in sublayerMap.keys where !live.contains(id) {
            sublayerMap[id] = nil
            shownImages[id] = nil
        }
        contentView.layer.sublayers = ordered
        checkerView.isHidden = !model.hasDocument
        updateSelectionDisplay()
        overlay.setNeedsDisplay()
    }

    private func updateSelectionDisplay() {
        overlay.updateAnts(path: model.selection, transform: docToView)
        if let s = model.selection {
            strokeMask.path = s
            strokeLayer.mask = strokeMask
        } else {
            strokeLayer.mask = nil
        }
    }

    // MARK: - Layout & transform

    override func layoutSubviews() {
        super.layoutSubviews()
        overlay.frame = bounds
        if bounds.size != lastBoundsSize {
            lastBoundsSize = bounds.size
            fitToScreen()
        }
    }

    func fitToScreen() {
        guard bounds.width > 0, bounds.height > 0, docSize.width > 0, docSize.height > 0 else { return }
        let sa = safeAreaInsets
        let avail = CGRect(x: sa.left + 96,
                           y: sa.top + 84,
                           width: bounds.width - sa.left - sa.right - 96 - 32,
                           height: bounds.height - sa.top - sa.bottom - 84 - 120)
        guard avail.width > 10, avail.height > 10 else { return }
        let s = min(avail.width / docSize.width, avail.height / docSize.height)
        scale = s
        offset = CGPoint(x: avail.midX - docSize.width * s / 2, y: avail.midY - docSize.height * s / 2)
        applyTransform()
    }

    private var minScale: CGFloat {
        guard docSize.width > 0 else { return 0.01 }
        return min(0.5, 120 / max(docSize.width, docSize.height))
    }

    private func applyTransform() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentView.transform = .identity
        contentView.layer.position = offset
        contentView.transform = CGAffineTransform(scaleX: scale, y: scale)
        let frame = CGRect(x: offset.x, y: offset.y, width: docSize.width * scale, height: docSize.height * scale)
        checkerView.frame = frame
        checkerView.layer.shadowPath = UIBezierPath(rect: checkerView.bounds).cgPath
        let nearest = scale >= 2.5
        for (_, l) in sublayerMap { l.magnificationFilter = nearest ? .nearest : .linear }
        updateSelectionDisplay()
        overlay.setNeedsDisplay()
        CATransaction.commit()
    }

    private func docPoint(_ v: CGPoint) -> CGPoint {
        CGPoint(x: (v.x - offset.x) / scale, y: (v.y - offset.y) / scale)
    }

    private func viewPoint(_ d: CGPoint) -> CGPoint {
        CGPoint(x: d.x * scale + offset.x, y: d.y * scale + offset.y)
    }

    // MARK: - Gestures

    private func setupGestures() {
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        addGestureRecognizer(pinch)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 3
        pan.delegate = self
        addGestureRecognizer(pan)

        let twoTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap))
        twoTap.numberOfTouchesRequired = 2
        twoTap.delegate = self
        addGestureRecognizer(twoTap)

        let threeTap = UITapGestureRecognizer(target: self, action: #selector(handleThreeFingerTap))
        threeTap.numberOfTouchesRequired = 3
        threeTap.delegate = self
        addGestureRecognizer(threeTap)

        let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
        addGestureRecognizer(hover)
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        guard docSize.width > 0 else { return }
        if g.state == .began || g.state == .changed {
            let loc = g.location(in: self)
            let newScale = (scale * g.scale).clamped(minScale, 40)
            let f = newScale / scale
            offset = CGPoint(x: loc.x - (loc.x - offset.x) * f, y: loc.y - (loc.y - offset.y) * f)
            scale = newScale
            g.scale = 1
            applyTransform()
        }
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: self)
        offset = offset + t
        g.setTranslation(.zero, in: self)
        applyTransform()
    }

    @objc private func handleTwoFingerTap() { model.undo() }
    @objc private func handleThreeFingerTap() { model.redo() }

    @objc private func handleHover(_ g: UIHoverGestureRecognizer) {
        switch g.state {
        case .began, .changed: hoverPoint = g.location(in: self)
        default: hoverPoint = nil
        }
        overlay.setNeedsDisplay()
    }

    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        model.tool = (model.tool == .eraser) ? model.previousBrushToolForToggle : .eraser
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard model.hasDocument, activeTouch == nil, let t = touches.first else { return }
        if let all = event?.allTouches, all.count > 1 { return }
        activeTouch = t
        begin(t)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = activeTouch, touches.contains(t) else { return }
        if mode == .brush || mode == .eraser {
            let samples = event?.coalescedTouches(for: t) ?? [t]
            for s in samples { moved(s) }
        } else {
            moved(t)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = activeTouch, touches.contains(t) else { return }
        end(t)
        activeTouch = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = activeTouch, touches.contains(t) else { return }
        cancel()
        activeTouch = nil
    }

    private func begin(_ t: UITouch) {
        let vp = t.location(in: self)
        let p = docPoint(vp)
        startDoc = p
        startView = vp
        lastView = vp

        if model.panel != .none {
            mode = .pan
            return
        }
        let paintTool = model.tool == .brush || model.tool == .eraser || model.tool == .eyedropper
        if t.type == .direct && !model.fingerDraws && paintTool {
            mode = .pan
            return
        }

        switch model.tool {
        case .brush: beginBrush(p, t)
        case .eraser: beginEraser(p, t)
        case .eyedropper:
            mode = .eyedrop
            model.pickColor(at: p)
        case .select: beginSelection(p, vp, t)
        case .move:
            guard model.activeLayer != nil else { return }
            mode = .move
            moveOffset = .zero
        case .crop: beginCrop(vp)
        }
    }

    private func moved(_ t: UITouch) {
        let vp = t.location(in: self)
        let p = docPoint(vp)
        switch mode {
        case .brush:
            if let ctx = strokeContext {
                addPoint(p, pressure: pressure(of: t), into: ctx)
                strokeDirty = true
            }
        case .eraser:
            if let l = directLayer {
                addPoint(p, pressure: pressure(of: t), into: l.context)
                l.markDirty()
                directDirty = true
            }
        case .eyedrop:
            model.pickColor(at: p)
        case .shapeSelect:
            model.dragPreview = shapePath(from: startDoc, to: p)
            overlay.setNeedsDisplay()
        case .lasso:
            if let last = lassoPoints.last, last.distance(to: p) * scale > 2 {
                lassoPoints.append(p)
                model.dragPreview = PathBuilder.polyline(lassoPoints, closed: false)
                overlay.setNeedsDisplay()
            }
        case .pointDrag:
            if vp.distance(to: startView) > 4 { dragMoved = true }
            if (dragMoved || dragIsNew), model.pendingPoints.indices.contains(dragIndex) {
                model.pendingPoints[dragIndex].p = clampToDoc(p)
                overlay.setNeedsDisplay()
            }
        case .move:
            moveOffset = CGPoint(x: (p.x - startDoc.x).rounded(), y: (p.y - startDoc.y).rounded())
            if let id = model.activeLayer?.id {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                sublayerMap[id]?.position = moveOffset
                CATransaction.commit()
            }
        case .crop:
            updateCrop(p)
        case .pan:
            offset = offset + (vp - lastView)
            applyTransform()
        case .none:
            break
        }
        lastView = vp
    }

    private func end(_ t: UITouch) {
        let vp = t.location(in: self)
        let p = docPoint(vp)
        switch mode {
        case .brush:
            finishBrush()
        case .eraser:
            if let l = directLayer { model.endDirectStroke(l) }
            directLayer = nil
            directDirty = false
            forceSync()
        case .eyedrop:
            model.finishEyedropper()
        case .shapeSelect:
            model.dragPreview = nil
            if startView.distance(to: vp) < 4 {
                model.deselect()
            } else {
                model.applySelection(shapePath(from: startDoc, to: p))
            }
        case .lasso:
            model.dragPreview = nil
            let path = PathBuilder.polyline(lassoPoints, closed: true)
            let b = path.boundingBoxOfPath
            if lassoPoints.count >= 3 && b.width * scale > 4 && b.height * scale > 4 {
                model.applySelection(path)
            } else {
                model.deselect()
            }
            lassoPoints = []
        case .pointDrag:
            if !dragMoved && !dragIsNew {
                if t.tapCount >= 2 {
                    model.toggleSmooth(dragIndex)
                } else if dragIndex == 0 && model.pendingPoints.count >= 3 {
                    model.closePendingPoints()
                }
            }
        case .move:
            let d = moveOffset
            moveOffset = .zero
            mode = .none
            model.translateActiveLayer(by: d)
            forceSync()
        case .crop, .pan, .none:
            break
        }
        mode = .none
        overlay.setNeedsDisplay()
    }

    private func cancel() {
        switch mode {
        case .brush:
            strokeContext?.clear(CGRect(origin: .zero, size: docSize))
            strokeLayer.contents = nil
            strokeDirty = false
            lastStamp = nil
        case .eraser:
            if let l = directLayer { model.cancelDirectStroke(l) }
            directLayer = nil
            directDirty = false
            forceSync()
        case .shapeSelect, .lasso:
            model.dragPreview = nil
            lassoPoints = []
        case .pointDrag:
            if dragIsNew, model.pendingPoints.indices.contains(dragIndex) {
                model.pendingPoints.remove(at: dragIndex)
            }
        case .move:
            moveOffset = .zero
            mode = .none
            forceSync()
        case .eyedrop, .crop, .pan, .none:
            break
        }
        mode = .none
        overlay.setNeedsDisplay()
    }

    private func clampToDoc(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x.clamped(0, docSize.width), y: p.y.clamped(0, docSize.height))
    }

    // MARK: - Brush engine

    private func pressure(of t: UITouch) -> CGFloat {
        guard t.type == .pencil, t.maximumPossibleForce > 0 else { return 1 }
        return (t.force / (t.maximumPossibleForce * 0.55)).clamped(0.05, 1)
    }

    private func ensureStrokeContext() -> CGContext {
        let w = Int(docSize.width), h = Int(docSize.height)
        if let c = strokeContext, c.width == w, c.height == h { return c }
        let c = PaintLayer.makeContext(width: w, height: h)
        strokeContext = c
        return c
    }

    private func makeGradient(color: CGColor, hardness: CGFloat, alpha: CGFloat) -> CGGradient? {
        let h = hardness.clamped(0, 0.97)
        var colors: [CGColor] = []
        var locations: [CGFloat] = []
        guard let solid = color.copy(alpha: alpha) else { return nil }
        colors.append(solid); locations.append(0)
        colors.append(solid); locations.append(h)
        let steps = 6
        for i in 1...steps {
            let f = CGFloat(i) / CGFloat(steps)
            let falloff = 1 - (3 * f * f - 2 * f * f * f)
            if let c = color.copy(alpha: alpha * falloff) {
                colors.append(c)
                locations.append(h + (1 - h) * f)
            }
        }
        return CGGradient(colorsSpace: PaintLayer.colorSpace, colors: colors as CFArray, locations: locations)
    }

    private func beginBrush(_ p: CGPoint, _ t: UITouch) {
        let ctx = ensureStrokeContext()
        ctx.clear(CGRect(origin: .zero, size: docSize))
        strokeSettings = model.brush
        strokeColor = UIColor(model.color).cgColor
        strokeGradient = makeGradient(color: strokeColor, hardness: strokeSettings.hardness, alpha: 1)
        strokeLayer.opacity = Float(strokeSettings.opacity)
        lastStamp = nil
        mode = .brush
        addPoint(p, pressure: pressure(of: t), into: ctx)
        strokeDirty = true
    }

    private func beginEraser(_ p: CGPoint, _ t: UITouch) {
        guard let l = model.beginDirectStroke() else { return }
        directLayer = l
        strokeSettings = model.eraser
        strokeColor = UIColor.black.cgColor
        strokeGradient = makeGradient(color: strokeColor, hardness: strokeSettings.hardness, alpha: strokeSettings.opacity)
        lastStamp = nil
        mode = .eraser
        addPoint(p, pressure: pressure(of: t), into: l.context)
        l.markDirty()
        directDirty = true
    }

    private func radius(for pressure: CGFloat) -> CGFloat {
        let base = strokeSettings.size / 2
        let factor = strokeSettings.pressureSize ? (0.2 + 0.8 * pressure) : 1
        return max(0.5, base * factor)
    }

    private func spacing(for pressure: CGFloat) -> CGFloat {
        let k: CGFloat = strokeSettings.hardness >= 0.98 ? 0.1 : 0.15
        return max(0.5, radius(for: pressure) * 2 * k)
    }

    private func stamp(_ p: CGPoint, pressure: CGFloat, into ctx: CGContext) {
        let r = radius(for: pressure)
        let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        if strokeSettings.hardness >= 0.98 || strokeGradient == nil {
            let alpha = mode == .eraser ? strokeSettings.opacity : 1
            ctx.setFillColor(strokeColor.copy(alpha: alpha) ?? strokeColor)
            ctx.fillEllipse(in: rect)
        } else if let g = strokeGradient {
            ctx.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: r, options: [])
        }
    }

    private func addPoint(_ p: CGPoint, pressure: CGFloat, into ctx: CGContext) {
        guard let last = lastStamp else {
            stamp(p, pressure: pressure, into: ctx)
            lastStamp = p
            lastPressure = pressure
            spacingLeft = spacing(for: pressure)
            return
        }
        let d = last.distance(to: p)
        guard d > 0.0001 else { return }
        var pos = spacingLeft
        while pos <= d {
            let f = pos / d
            let q = CGPoint(x: last.x + (p.x - last.x) * f, y: last.y + (p.y - last.y) * f)
            let pr = lastPressure + (pressure - lastPressure) * f
            stamp(q, pressure: pr, into: ctx)
            pos += spacing(for: pr)
        }
        spacingLeft = pos - d
        lastStamp = p
        lastPressure = pressure
    }

    private func finishBrush() {
        defer {
            strokeDirty = false
            lastStamp = nil
        }
        guard let ctx = strokeContext, lastStamp != nil, let img = ctx.makeImage() else {
            strokeLayer.contents = nil
            return
        }
        model.commitStroke(img, opacity: strokeSettings.opacity)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        needsSyncFlag = false
        sync()
        strokeLayer.contents = nil
        CATransaction.commit()
        ctx.clear(CGRect(origin: .zero, size: docSize))
    }

    // MARK: - Selection tools

    private func beginSelection(_ p: CGPoint, _ vp: CGPoint, _ t: UITouch) {
        switch model.selectionShape {
        case .rect, .ellipse:
            mode = .shapeSelect
        case .lasso:
            mode = .lasso
            lassoPoints = [p]
        case .points, .curve:
            mode = .pointDrag
            dragMoved = false
            let hitRadius: CGFloat = 26
            var bestIndex: Int?
            var bestDist = CGFloat.greatestFiniteMagnitude
            for (i, sp) in model.pendingPoints.enumerated() {
                let d = viewPoint(sp.p).distance(to: vp)
                if d < hitRadius && d < bestDist {
                    bestDist = d
                    bestIndex = i
                }
            }
            if let idx = bestIndex {
                dragIndex = idx
                dragIsNew = false
            } else {
                model.pendingPoints.append(SelPoint(p: clampToDoc(p), smooth: model.selectionShape == .curve))
                dragIndex = model.pendingPoints.count - 1
                dragIsNew = true
            }
            overlay.setNeedsDisplay()
        }
    }

    private func shapePath(from a: CGPoint, to b: CGPoint) -> CGPath {
        let r = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
        return model.selectionShape == .ellipse ? CGPath(ellipseIn: r, transform: nil) : CGPath(rect: r, transform: nil)
    }

    // MARK: - Crop tool

    private func beginCrop(_ vp: CGPoint) {
        let r = model.cropRect
        let vr = r.applying(docToView)
        cropStart = r
        mode = .crop
        let corners: [(CropHandle, CGPoint)] = [
            (.topLeft, CGPoint(x: vr.minX, y: vr.minY)),
            (.topRight, CGPoint(x: vr.maxX, y: vr.minY)),
            (.bottomLeft, CGPoint(x: vr.minX, y: vr.maxY)),
            (.bottomRight, CGPoint(x: vr.maxX, y: vr.maxY))
        ]
        if let c = corners.min(by: { $0.1.distance(to: vp) < $1.1.distance(to: vp) }), c.1.distance(to: vp) < 36 {
            cropHandle = c.0
            return
        }
        let tol: CGFloat = 24
        let inX = vp.x > vr.minX && vp.x < vr.maxX
        let inY = vp.y > vr.minY && vp.y < vr.maxY
        if abs(vp.y - vr.minY) < tol && inX { cropHandle = .top }
        else if abs(vp.y - vr.maxY) < tol && inX { cropHandle = .bottom }
        else if abs(vp.x - vr.minX) < tol && inY { cropHandle = .left }
        else if abs(vp.x - vr.maxX) < tol && inY { cropHandle = .right }
        else if vr.contains(vp) { cropHandle = .inside }
        else {
            cropHandle = .none
            mode = .none
        }
    }

    private func updateCrop(_ p: CGPoint) {
        let d = p - startDoc
        let W = docSize.width, H = docSize.height
        let minS = max(8, 32 / scale)
        let ratio = model.cropRatio.value(width: W, height: H)
        var r = cropStart

        switch cropHandle {
        case .none:
            return
        case .inside:
            r.origin.x = (cropStart.minX + d.x).clamped(0, W - r.width)
            r.origin.y = (cropStart.minY + d.y).clamped(0, H - r.height)
        case .top, .bottom, .left, .right:
            if ratio != nil { return }
            var minX = cropStart.minX, minY = cropStart.minY, maxX = cropStart.maxX, maxY = cropStart.maxY
            switch cropHandle {
            case .top: minY = (minY + d.y).clamped(0, maxY - minS)
            case .bottom: maxY = (maxY + d.y).clamped(minY + minS, H)
            case .left: minX = (minX + d.x).clamped(0, maxX - minS)
            case .right: maxX = (maxX + d.x).clamped(minX + minS, W)
            default: break
            }
            r = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            let anchor: CGPoint
            let moving: CGPoint
            switch cropHandle {
            case .topLeft:
                anchor = CGPoint(x: cropStart.maxX, y: cropStart.maxY)
                moving = CGPoint(x: cropStart.minX, y: cropStart.minY)
            case .topRight:
                anchor = CGPoint(x: cropStart.minX, y: cropStart.maxY)
                moving = CGPoint(x: cropStart.maxX, y: cropStart.minY)
            case .bottomLeft:
                anchor = CGPoint(x: cropStart.maxX, y: cropStart.minY)
                moving = CGPoint(x: cropStart.minX, y: cropStart.maxY)
            default:
                anchor = CGPoint(x: cropStart.minX, y: cropStart.minY)
                moving = CGPoint(x: cropStart.maxX, y: cropStart.maxY)
            }
            let target = moving + d
            let sx: CGFloat = target.x >= anchor.x ? 1 : -1
            let sy: CGFloat = target.y >= anchor.y ? 1 : -1
            var w = abs(target.x - anchor.x)
            var h = abs(target.y - anchor.y)
            let maxW = sx > 0 ? W - anchor.x : anchor.x
            let maxH = sy > 0 ? H - anchor.y : anchor.y
            if let ratio {
                w = max(w, h * ratio)
                w = min(w, maxW, maxH * ratio)
                w = max(w, minS)
                h = w / ratio
            } else {
                w = min(max(w, minS), maxW)
                h = min(max(h, minS), maxH)
            }
            r = CGRect(x: sx > 0 ? anchor.x : anchor.x - w,
                       y: sy > 0 ? anchor.y : anchor.y - h,
                       width: w, height: h)
        }
        model.cropRect = r
        overlay.setNeedsDisplay()
    }
}

extension EditorModel {
    /// Tool to return to when the Pencil double-tap toggles off the eraser.
    var previousBrushToolForToggle: Tool { .brush }
}
