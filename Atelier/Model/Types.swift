import CoreGraphics
import Foundation

enum Tool: String, CaseIterable, Identifiable {
    case brush, eraser, eyedropper, select, move, crop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .brush: return "Pinceau"
        case .eraser: return "Gomme"
        case .eyedropper: return "Pipette"
        case .select: return "Sélection"
        case .move: return "Déplacer"
        case .crop: return "Recadrer"
        }
    }

    var icon: String {
        switch self {
        case .brush: return "paintbrush.pointed.fill"
        case .eraser: return "eraser.fill"
        case .eyedropper: return "eyedropper"
        case .select: return "lasso"
        case .move: return "arrow.up.and.down.and.arrow.left.and.right"
        case .crop: return "crop"
        }
    }
}

enum SelectionShape: String, CaseIterable, Identifiable {
    case points, curve, lasso, rect, ellipse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .points: return "Points"
        case .curve: return "Courbe"
        case .lasso: return "Lasso"
        case .rect: return "Rectangle"
        case .ellipse: return "Ellipse"
        }
    }

    var icon: String {
        switch self {
        case .points: return "pentagon"
        case .curve: return "point.topleft.down.curvedto.point.bottomright.up"
        case .lasso: return "scribble"
        case .rect: return "rectangle.dashed"
        case .ellipse: return "circle.dashed"
        }
    }

    var hint: String {
        switch self {
        case .points: return "Touchez pour poser des points · touchez le 1er point pour fermer"
        case .curve: return "Points lissés en courbe · double-touchez un point pour le passer en angle"
        case .lasso: return "Dessinez librement le contour"
        case .rect, .ellipse: return "Glissez pour tracer · une touche simple désélectionne"
        }
    }
}

enum SelectionCombine: String, CaseIterable, Identifiable {
    case replace, add, subtract

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .replace: return "square"
        case .add: return "plus.square"
        case .subtract: return "minus.square"
        }
    }

    var title: String {
        switch self {
        case .replace: return "Nouvelle"
        case .add: return "Ajouter"
        case .subtract: return "Soustraire"
        }
    }
}

enum CropRatio: String, CaseIterable, Identifiable {
    case free, original, square, r4x3, r3x2, r16x9

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: return "Libre"
        case .original: return "Original"
        case .square: return "1:1"
        case .r4x3: return "4:3"
        case .r3x2: return "3:2"
        case .r16x9: return "16:9"
        }
    }

    /// Width / height ratio, oriented like the document.
    func value(width: CGFloat, height: CGFloat) -> CGFloat? {
        guard width > 0, height > 0 else { return nil }
        let base: CGFloat
        switch self {
        case .free: return nil
        case .original: return width / height
        case .square: return 1
        case .r4x3: base = 4.0 / 3.0
        case .r3x2: base = 3.0 / 2.0
        case .r16x9: base = 16.0 / 9.0
        }
        return width >= height ? base : 1 / base
    }
}

enum Panel: Equatable {
    case none, sharpen
}

enum ExportKind {
    case jpeg, png, activeLayer, eachLayer, clipboard
}

struct BrushSettings: Equatable {
    var size: CGFloat = 24
    var opacity: CGFloat = 1
    var hardness: CGFloat = 0.8
    var pressureSize: Bool = true
}

struct SelPoint: Equatable {
    var p: CGPoint
    var smooth: Bool
}

struct LayerPreview {
    let layerID: UUID
    let image: CGImage
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct LayerSnapshot {
    let id: UUID
    let name: String
    let isVisible: Bool
    let opacity: Double
    let image: CGImage
}

struct DocSnapshot {
    let width: Int
    let height: Int
    let layers: [LayerSnapshot]
    let activeLayerID: UUID?
    let selection: CGPath?
}
