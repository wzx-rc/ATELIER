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

enum Theme {
    static let accent = Color(red: 1.0, green: 0.74, blue: 0.38)
    static let accentUIColor = UIColor(red: 1.0, green: 0.74, blue: 0.38, alpha: 1)
    static let panelStroke = Color.white.opacity(0.09)
}

extension View {
    func glass(_ radius: CGFloat = 18) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.panelStroke, lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 8)
    }

    func glassCapsule() -> some View {
        self
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.panelStroke, lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 8)
    }
}
