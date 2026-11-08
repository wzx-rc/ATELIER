import CoreGraphics
import SwiftUI
import UIKit

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x * s, y: a.y * s) }
    static func / (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x / s, y: a.y / s) }

    func distance(to o: CGPoint) -> CGFloat { hypot(x - o.x, y - o.y) }
}

extension Comparable {
    func clamped(_ lo: Self, _ hi: Self) -> Self { min(max(self, lo), hi) }
}

/// Wrapper used to hand non-Sendable CoreGraphics objects to background work.
struct Unchecked<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

@MainActor
enum CheckerPattern {
    static let image: UIImage = CanvasView.checkerTile()
}

extension Color {
    /// Builds a color from a 0xRRGGBB value.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// Direction « V4 » : gris bleuté, accent cyan adouci, contrôles arrondis.
enum Theme {
    static let workspace = Color(hex: 0x14181C)      // plan de travail
    static let bar = Color(hex: 0x1B2126)            // barres et panneaux ancrés
    static let raised = Color(hex: 0x1F252B)         // éléments flottants (barre d'actions, fenêtres)
    static let control = Color(hex: 0x232A31)        // boutons secondaires
    static let field = Color(hex: 0x161B20)          // champs de valeur
    static let border = Color(hex: 0x34404A)         // bordures, segment actif
    static let divider = Color(hex: 0x262E35)        // filets entre zones
    static let softDivider = Color(hex: 0x2C353D)    // filets internes
    static let text = Color(hex: 0xE8EDF0)
    static let textSecondary = Color(hex: 0xA9B5BD)
    static let textMuted = Color(hex: 0x95A2AB)
    static let disabled = Color(hex: 0x5C6A74)
    static let accent = Color(hex: 0x3FC1D9)
    static let accentText = Color(hex: 0x5FD0E4)
    static let accentTint = Color(hex: 0x3FC1D9, opacity: 0.14)
    static let onAccent = Color(hex: 0x0B1A20)
    static let accentUIColor = UIColor(red: 63 / 255, green: 193 / 255, blue: 217 / 255, alpha: 1)
    static let panelStroke = Color(hex: 0x2C353D)

    // Dimensions de la mise en page
    static let topBarHeight: CGFloat = 52
    static let documentStripHeight: CGFloat = 34
    static let railWidth: CGFloat = 52
    static let sidePanelWidth: CGFloat = 300
    static let statusBarHeight: CGFloat = 28
}

extension View {
    /// Surface flottante (barre d'actions, fenêtres, toasts).
    func glass(_ radius: CGFloat = 14) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.raised))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.panelStroke, lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 14, x: 0, y: 8)
    }

    func glassCapsule() -> some View {
        self
            .background(Capsule().fill(Theme.raised))
            .overlay(Capsule().strokeBorder(Theme.panelStroke, lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 14, x: 0, y: 8)
    }
}

/// Logo d'Atelier : hexagone et « A » au trait.
struct AppMark: View {
    var size: CGFloat = 20
    var lineWidth: CGFloat = 1.6

    var body: some View {
        Canvas { ctx, sz in
            let k = sz.width / 26
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * k, y: y * k) }
            var hex = Path()
            hex.move(to: p(13, 2))
            hex.addLine(to: p(22.5, 7.5))
            hex.addLine(to: p(22.5, 18.5))
            hex.addLine(to: p(13, 24))
            hex.addLine(to: p(3.5, 18.5))
            hex.addLine(to: p(3.5, 7.5))
            hex.closeSubpath()
            var letter = Path()
            letter.move(to: p(9, 17))
            letter.addLine(to: p(13, 8))
            letter.addLine(to: p(17, 17))
            letter.move(to: p(10.5, 14))
            letter.addLine(to: p(15.5, 14))
            let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            ctx.stroke(hex, with: .color(Theme.accentText), style: style)
            ctx.stroke(letter, with: .color(Theme.accentText), style: style)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Rectangle aux coins supérieurs arrondis (onglet de document).
struct TopRoundedRect: Shape {
    var radius: CGFloat = 8

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + radius))
        p.addQuadCurve(to: CGPoint(x: r.minX + radius, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + radius), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}
