import UIKit

/// Screen-space overlay: marching ants, point-path editor, crop frame, brush cursor.
final class CanvasOverlayView: UIView {
    weak var canvas: CanvasView?

    private let antsBase = CAShapeLayer()
    private let antsDash = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw

        for l in [antsBase, antsDash] {
            l.fillColor = nil
            l.lineWidth = 1.25
            l.actions = ["path": NSNull(), "bounds": NSNull(), "position": NSNull()]
            layer.addSublayer(l)
        }
        antsBase.strokeColor = UIColor.black.withAlphaComponent(0.85).cgColor
        antsDash.strokeColor = UIColor.white.cgColor
        antsDash.lineDashPattern = [6, 5]
        startAnts()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func startAnts() {
        let anim = CABasicAnimation(keyPath: "lineDashPhase")
        anim.fromValue = 0
        anim.toValue = 11
        anim.duration = 0.7
        anim.repeatCount = .infinity
        anim.isRemovedOnCompletion = false
        antsDash.add(anim, forKey: "ants")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil && antsDash.animation(forKey: "ants") == nil { startAnts() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        antsBase.frame = bounds
        antsDash.frame = bounds
    }

    func updateAnts(path: CGPath?, transform: CGAffineTransform) {
        var t = transform
        var p: CGPath?
        if let path { p = path.copy(using: &t) }
        antsBase.path = p
        antsDash.path = p
    }

    override func draw(_ rect: CGRect) {
        guard let canvas, let ctx = UIGraphicsGetCurrentContext() else { return }
        let model = canvas.model
        guard model.hasDocument else { return }
        let t = canvas.docToView

        if model.tool == .crop {
            drawCrop(ctx, rect: model.cropRect.applying(t))
        }

        if let preview = model.dragPreview {
            var tt = t
            if let vp = preview.copy(using: &tt) {
                ctx.saveGState()
                ctx.addPath(vp)
                ctx.setStrokeColor(UIColor.black.withAlphaComponent(0.7).cgColor)
                ctx.setLineWidth(2.5)
                ctx.strokePath()
                ctx.addPath(vp)
                ctx.setStrokeColor(UIColor.white.cgColor)
                ctx.setLineWidth(1.2)
                ctx.setLineDash(phase: 0, lengths: [5, 4])
                ctx.strokePath()
                ctx.restoreGState()
            }
        }

        if model.tool == .select && !model.pendingPoints.isEmpty {
            drawPendingPoints(ctx, points: model.pendingPoints.map { SelPoint(p: $0.p.applying(t), smooth: $0.smooth) })
        }

        if model.tool == .brush || model.tool == .eraser {
            let settings = model.tool == .brush ? model.brush : model.eraser
            let r = max(1, settings.size / 2 * canvas.scale)
            if model.showBrushPreview {
                ring(ctx, center: CGPoint(x: bounds.midX, y: bounds.midY), radius: r)
            }
            if let hp = canvas.hoverPoint {
                ring(ctx, center: hp, radius: r)
            }
        }
    }

    private func ring(_ ctx: CGContext, center c: CGPoint, radius r: CGFloat) {
        let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        ctx.saveGState()
        ctx.setLineWidth(2.5)
        ctx.setStrokeColor(UIColor.black.withAlphaComponent(0.5).cgColor)
        ctx.strokeEllipse(in: rect)
        ctx.setLineWidth(1)
        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.strokeEllipse(in: rect)
        ctx.restoreGState()
    }

    private func drawPendingPoints(_ ctx: CGContext, points pts: [SelPoint]) {
        let accent = Theme.accentUIColor
        ctx.saveGState()
        let open = PathBuilder.path(points: pts, closed: false)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        ctx.addPath(open)
        ctx.setStrokeColor(UIColor.black.withAlphaComponent(0.6).cgColor)
        ctx.setLineWidth(3.5)
        ctx.strokePath()
        ctx.addPath(open)
        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(1.5)
        ctx.strokePath()

        if pts.count >= 2, let last = pts.last {
            ctx.setLineDash(phase: 0, lengths: [4, 5])
            ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.55).cgColor)
            ctx.setLineWidth(1)
            ctx.move(to: last.p)
            ctx.addLine(to: pts[0].p)
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
        }

        for (i, sp) in pts.enumerated() {
            // Repères discrets (le dessin seulement : la zone de prise au doigt reste large).
            let r: CGFloat = i == 0 ? 4.5 : 3.5
            let rr = CGRect(x: sp.p.x - r, y: sp.p.y - r, width: 2 * r, height: 2 * r)
            let shape = sp.smooth ? UIBezierPath(ovalIn: rr) : UIBezierPath(roundedRect: rr, cornerRadius: 1)
            let fill = (i == 0 && pts.count >= 3) ? accent : UIColor.white
            fill.setFill()
            shape.fill()
            UIColor.black.withAlphaComponent(0.7).setStroke()
            shape.lineWidth = 1
            shape.stroke()
        }
        ctx.restoreGState()
    }

    private func drawCrop(_ ctx: CGContext, rect vr: CGRect) {
        ctx.saveGState()
        ctx.addRect(bounds)
        ctx.addRect(vr)
        ctx.setFillColor(UIColor.black.withAlphaComponent(0.55).cgColor)
        ctx.fillPath(using: .evenOdd)

        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.35).cgColor)
        ctx.setLineWidth(1)
        for i in 1...2 {
            let f = CGFloat(i) / 3
            let x = vr.minX + vr.width * f
            let y = vr.minY + vr.height * f
            ctx.move(to: CGPoint(x: x, y: vr.minY))
            ctx.addLine(to: CGPoint(x: x, y: vr.maxY))
            ctx.move(to: CGPoint(x: vr.minX, y: y))
            ctx.addLine(to: CGPoint(x: vr.maxX, y: y))
        }
        ctx.strokePath()

        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(vr)

        let L = min(24, vr.width / 3, vr.height / 3)
        ctx.setLineWidth(4)
        ctx.setLineCap(.round)
        ctx.setStrokeColor(UIColor.white.cgColor)
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: vr.minX, y: vr.minY), 1, 1),
            (CGPoint(x: vr.maxX, y: vr.minY), -1, 1),
            (CGPoint(x: vr.minX, y: vr.maxY), 1, -1),
            (CGPoint(x: vr.maxX, y: vr.maxY), -1, -1)
        ]
        for (c, sx, sy) in corners {
            ctx.move(to: CGPoint(x: c.x + sx * L, y: c.y))
            ctx.addLine(to: c)
            ctx.addLine(to: CGPoint(x: c.x, y: c.y + sy * L))
        }
        ctx.strokePath()
        ctx.restoreGState()
    }
}
