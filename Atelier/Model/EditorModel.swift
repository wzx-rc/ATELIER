import SwiftUI
import UIKit
import PhotosUI

@MainActor
final class EditorModel: ObservableObject {

    // MARK: Document

    @Published private(set) var docWidth = 0
    @Published private(set) var docHeight = 0
    @Published var layers: [PaintLayer] = []   // bottom → top
    @Published var activeLayerID: UUID?

    var hasDocument: Bool { docWidth > 0 && docHeight > 0 && !layers.isEmpty }
    var docRect: CGRect { CGRect(x: 0, y: 0, width: docWidth, height: docHeight) }
    var activeLayer: PaintLayer? { layers.first { $0.id == activeLayerID } ?? layers.last }

    // MARK: Tools

    @Published var tool: Tool = .brush {
        didSet { toolDidChange(from: oldValue) }
    }
    @Published var brush = BrushSettings()
    @Published var eraser = BrushSettings(size: 60, opacity: 1, hardness: 0.6, pressureSize: false)
    @Published var color: Color = Color(red: 0.95, green: 0.35, blue: 0.3)
    @Published var recentColors: [Color] = [.white, .black, Color(red: 0.95, green: 0.35, blue: 0.3), Color(red: 0.25, green: 0.55, blue: 0.95)]
    @Published var fingerDraws = true
    @Published var showBrushPreview = false
    private(set) var previousPaintTool: Tool = .brush

    // MARK: Selection

    @Published var selectionShape: SelectionShape = .points {
        didSet { if oldValue != selectionShape { pendingPoints = [] } }
    }
    @Published var combine: SelectionCombine = .replace
    @Published var selection: CGPath?
    @Published var pendingPoints: [SelPoint] = []
    @Published var dragPreview: CGPath?

    // MARK: Crop

    @Published var cropRect: CGRect = .zero
    @Published var cropRatio: CropRatio = .free {
        didSet { if oldValue != cropRatio { applyRatio() } }
    }

    // MARK: Panels / filters

    @Published var panel: Panel = .none
    @Published var sharpenRadius: Double = 2.0
    @Published var sharpenAmount: Double = 0.8
    @Published var preview: LayerPreview?
    private var sharpenTask: Task<Void, Never>?

    // MARK: Status

    @Published var busyMessage: String?
    @Published var busyProgress: Double?
    @Published var toast: String?
    @Published var showLayers = true
    @Published var sideTab: SideTab = .layers
    @Published var navigatorExpanded = true
    @Published private(set) var zoomPercent = 100
    /// Partie visible du document, en coordonnées document (pour le navigateur).
    @Published private(set) var viewport: CGRect = .zero
    @Published var shareItem: ShareItem?
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    weak var canvas: CanvasView?

    private var undoStack: [DocSnapshot] = []
    private var redoStack: [DocSnapshot] = []

    private var maxUndo: Int {
        let bytes = max(1, docWidth * docHeight * 4)
        return (700_000_000 / bytes).clamped(5, 30)
    }

    // MARK: - Helpers

    func changed() {
        objectWillChange.send()
        canvas?.setNeedsSync()
    }

    /// Appelé par le canvas après chaque zoom / déplacement de la vue.
    func updateViewport(scale: CGFloat, visible: CGRect) {
        let z = Int((scale * 100).rounded())
        if z != zoomPercent { zoomPercent = z }
        let r = visible.isNull ? CGRect.zero : visible.integral
        if r != viewport { viewport = r }
    }

    func showToast(_ text: String) {
        toast = text
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if self?.toast == text { self?.toast = nil }
        }
    }

    private func toolDidChange(from old: Tool) {
        if tool != .select {
            pendingPoints = []
            dragPreview = nil
        }
        if tool == .brush || tool == .eraser { previousPaintTool = tool }
        if tool == .crop && old != .crop { resetCrop() }
        if panel != .none { cancelSharpen() }
        canvas?.setNeedsSync()
    }

    private func insertAboveActive(_ layer: PaintLayer) {
        if let a = activeLayer, let i = layers.firstIndex(where: { $0.id == a.id }) {
            layers.insert(layer, at: i + 1)
        } else {
            layers.append(layer)
        }
        activeLayerID = layer.id
        changed()
    }

    // MARK: - Import

    func load(item: PhotosPickerItem, asLayer: Bool) {
        busyMessage = "Chargement…"
        busyProgress = nil
        Task {
            defer { busyMessage = nil }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let ui = UIImage(data: data),
                  let cg = ImageOps.normalized(ui) else {
                showToast("Impossible de charger l'image")
                return
            }
            if asLayer && hasDocument { addImageLayer(cg) } else { openImage(cg) }
        }
    }

    func pasteFromClipboard(asLayer: Bool) {
        guard let ui = UIPasteboard.general.image, let cg = ImageOps.normalized(ui) else {
            showToast("Aucune image dans le presse-papiers")
            return
        }
        if asLayer && hasDocument { addImageLayer(cg) } else { openImage(cg) }
    }

    func openImage(_ cg: CGImage) {
        let w = cg.width, h = cg.height
        let layer = PaintLayer(name: "Photo", width: w, height: h)
        layer.replace(with: cg)
        undoStack.removeAll()
        redoStack.removeAll()
        updateUndoFlags()
        preview = nil
        panel = .none
        selection = nil
        pendingPoints = []
        dragPreview = nil
        docWidth = w
        docHeight = h
        layers = [layer]
        activeLayerID = layer.id
        cropRect = docRect
        changed()
    }

    func addImageLayer(_ cg: CGImage) {
        pushUndo()
        let iw = CGFloat(cg.width), ih = CGFloat(cg.height)
        let s = min(1, CGFloat(docWidth) / iw, CGFloat(docHeight) / ih)
        let size = CGSize(width: iw * s, height: ih * s)
        let rect = CGRect(x: ((CGFloat(docWidth) - size.width) / 2).rounded(),
                          y: ((CGFloat(docHeight) - size.height) / 2).rounded(),
                          width: size.width, height: size.height)
        let layer = PaintLayer(name: "Photo \(layers.count + 1)", width: docWidth, height: docHeight)
        layer.drawImage(cg, in: rect)
        layer.markDirty()
        insertAboveActive(layer)
    }

    // MARK: - Undo

    private func snapshot() -> DocSnapshot {
        DocSnapshot(width: docWidth,
                    height: docHeight,
                    layers: layers.map {
                        LayerSnapshot(id: $0.id, name: $0.name, isVisible: $0.isVisible, opacity: $0.opacity, image: $0.image)
                    },
                    activeLayerID: activeLayerID,
                    selection: selection)
    }

    func pushUndo() {
        undoStack.append(snapshot())
        let limit = maxUndo
        if undoStack.count > limit { undoStack.removeFirst(undoStack.count - limit) }
        redoStack.removeAll()
        updateUndoFlags()
    }

    func undo() {
        guard hasDocument, let s = undoStack.popLast() else { return }
        cancelTransientState()
        redoStack.append(snapshot())
        restore(s)
        updateUndoFlags()
    }

    func redo() {
        guard hasDocument, let s = redoStack.popLast() else { return }
        cancelTransientState()
        undoStack.append(snapshot())
        restore(s)
        updateUndoFlags()
    }

    /// Restores the last pushed state without keeping a redo entry (used for cancelled strokes).
    func revertLastUndo() {
        guard let s = undoStack.popLast() else { return }
        restore(s)
        updateUndoFlags()
    }

    private func cancelTransientState() {
        preview = nil
        if panel != .none { panel = .none }
        pendingPoints = []
        dragPreview = nil
    }

    private func updateUndoFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    private func restore(_ s: DocSnapshot) {
        var result: [PaintLayer] = []
        for ls in s.layers {
            if let ex = layers.first(where: { $0.id == ls.id }), ex.width == s.width, ex.height == s.height {
                if ex.cachedImageIfAny !== ls.image { ex.replace(with: ls.image, adopt: true) }
                ex.name = ls.name
                ex.isVisible = ls.isVisible
                ex.opacity = ls.opacity
                result.append(ex)
            } else {
                let nl = PaintLayer(id: ls.id, name: ls.name, width: s.width, height: s.height)
                nl.replace(with: ls.image, adopt: true)
                nl.isVisible = ls.isVisible
                nl.opacity = ls.opacity
                result.append(nl)
            }
        }
        docWidth = s.width
        docHeight = s.height
        layers = result
        activeLayerID = s.activeLayerID
        selection = s.selection
        if tool == .crop { cropRect = docRect }
        changed()
    }

    // MARK: - Layers

    func addEmptyLayer() {
        guard hasDocument else { return }
        pushUndo()
        insertAboveActive(PaintLayer(name: "Calque \(layers.count + 1)", width: docWidth, height: docHeight))
    }

    func duplicateActiveLayer() {
        guard let l = activeLayer else { return }
        pushUndo()
        let c = PaintLayer(name: l.name + " copie", width: docWidth, height: docHeight)
        c.replace(with: l.image, adopt: true)
        c.opacity = l.opacity
        c.isVisible = l.isVisible
        insertAboveActive(c)
    }

    func deleteActiveLayer() {
        guard layers.count > 1, let l = activeLayer, let i = layers.firstIndex(where: { $0.id == l.id }) else { return }
        pushUndo()
        layers.remove(at: i)
        activeLayerID = layers[max(0, i - 1)].id
        changed()
    }

    func moveActiveLayer(up: Bool) {
        guard let l = activeLayer, let i = layers.firstIndex(where: { $0.id == l.id }) else { return }
        let j = up ? i + 1 : i - 1
        guard layers.indices.contains(j) else { return }
        pushUndo()
        layers.swapAt(i, j)
        changed()
    }

    func mergeDown() {
        guard let l = activeLayer, let i = layers.firstIndex(where: { $0.id == l.id }), i > 0 else { return }
        pushUndo()
        let below = layers[i - 1]
        if l.isVisible {
            below.context.saveGState()
            below.context.setAlpha(CGFloat(l.opacity))
            below.drawImage(l.image, in: below.docRect)
            below.context.restoreGState()
            below.markDirty()
        }
        layers.remove(at: i)
        activeLayerID = below.id
        changed()
    }

    func toggleVisibility(_ id: UUID) {
        guard let l = layers.first(where: { $0.id == id }) else { return }
        l.isVisible.toggle()
        changed()
    }

    func setOpacity(_ value: Double, for id: UUID) {
        guard let l = layers.first(where: { $0.id == id }) else { return }
        l.opacity = value
        changed()
    }

    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let l = layers.first(where: { $0.id == id }) else { return }
        l.name = trimmed
        changed()
    }

    func selectLayer(_ id: UUID) {
        guard activeLayerID != id else { return }
        if panel != .none { cancelSharpen() }
        activeLayerID = id
        changed()
    }

    // MARK: - Painting

    func commitStroke(_ strokeImage: CGImage, opacity: CGFloat) {
        guard let l = activeLayer else { return }
        pushUndo()
        let ctx = l.context
        ctx.saveGState()
        if let s = selection {
            ctx.addPath(s)
            ctx.clip()
        }
        ctx.setAlpha(opacity)
        l.drawImage(strokeImage, in: l.docRect)
        ctx.restoreGState()
        l.markDirty()
        noteColorUsed()
        changed()
    }

    func beginDirectStroke() -> PaintLayer? {
        guard let l = activeLayer else { return nil }
        pushUndo()
        let ctx = l.context
        ctx.saveGState()
        if let s = selection {
            ctx.addPath(s)
            ctx.clip()
        }
        ctx.setBlendMode(.destinationOut)
        return l
    }

    func endDirectStroke(_ l: PaintLayer) {
        l.context.restoreGState()
        l.markDirty()
        changed()
    }

    func cancelDirectStroke(_ l: PaintLayer) {
        l.context.restoreGState()
        revertLastUndo()
    }

    func noteColorUsed() {
        let c = color
        if recentColors.first == c { return }
        recentColors.removeAll { $0 == c }
        recentColors.insert(c, at: 0)
        if recentColors.count > 8 { recentColors.removeLast(recentColors.count - 8) }
    }

    func pickColor(at p: CGPoint) {
        let x = Int(p.x), y = Int(p.y)
        guard x >= 0, y >= 0, x < docWidth, y < docHeight else { return }
        var px = [UInt8](repeating: 0, count: 4)
        let visible = layers.filter { $0.isVisible }
        px.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: PaintLayer.colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.interpolationQuality = .none
            for l in visible {
                ctx.saveGState()
                ctx.setAlpha(CGFloat(l.opacity))
                ctx.draw(l.image, in: CGRect(x: -CGFloat(x), y: -CGFloat(l.height - y - 1),
                                             width: CGFloat(l.width), height: CGFloat(l.height)))
                ctx.restoreGState()
            }
        }
        let a = CGFloat(px[3])
        guard a > 0 else { return }
        let r = min(1, CGFloat(px[0]) / a), g = min(1, CGFloat(px[1]) / a), b = min(1, CGFloat(px[2]) / a)
        color = Color(uiColor: UIColor(displayP3Red: r, green: g, blue: b, alpha: 1))
    }

    func finishEyedropper() {
        noteColorUsed()
        tool = .brush
    }

    // MARK: - Selection

    func applySelection(_ path: CGPath) {
        var result: CGPath?
        switch combine {
        case .replace: result = path
        case .add: result = selection.map { $0.union(path) } ?? path
        case .subtract: result = selection.map { $0.subtracting(path) }
        }
        if let r = result {
            let b = r.boundingBoxOfPath
            if r.isEmpty || b.width < 1 || b.height < 1 { result = nil }
        }
        selection = result
    }

    func closePendingPoints() {
        guard pendingPoints.count >= 3 else { return }
        let path = PathBuilder.path(points: pendingPoints, closed: true)
        pendingPoints = []
        applySelection(path)
    }

    func removeLastPoint() {
        if !pendingPoints.isEmpty { pendingPoints.removeLast() }
    }

    func toggleSmooth(_ index: Int) {
        guard pendingPoints.indices.contains(index) else { return }
        pendingPoints[index].smooth.toggle()
    }

    func deselect() {
        selection = nil
        pendingPoints = []
    }

    func selectAll() {
        guard hasDocument else { return }
        selection = CGPath(rect: docRect, transform: nil)
    }

    func invertSelection() {
        guard hasDocument else { return }
        guard let s = selection else { selectAll(); return }
        let inv = CGPath(rect: docRect, transform: nil).subtracting(s)
        selection = inv.isEmpty ? nil : inv
    }

    /// Moves the selected pixels of the active layer into a new layer (or copies them).
    func cutSelection(copy: Bool) {
        guard let sel = selection, let src = activeLayer else { return }
        pushUndo()
        let piece = PaintLayer(name: copy ? "\(src.name) – copie" : "\(src.name) – découpe", width: docWidth, height: docHeight)
        let srcImage = src.image
        piece.context.saveGState()
        piece.context.addPath(sel)
        piece.context.clip()
        piece.drawImage(srcImage, in: piece.docRect)
        piece.context.restoreGState()
        piece.markDirty()
        if !copy {
            erase(path: sel, in: src)
        }
        selection = nil
        insertAboveActive(piece)
        showToast(copy ? "Copié sur un nouveau calque" : "Découpé sur un nouveau calque")
    }

    private func erase(path: CGPath, in layer: PaintLayer) {
        let ctx = layer.context
        ctx.saveGState()
        ctx.setBlendMode(.clear)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()
        layer.markDirty()
    }

    func deleteSelectionContent() {
        guard let sel = selection, let l = activeLayer else { return }
        pushUndo()
        erase(path: sel, in: l)
        changed()
    }

    func fillSelection() {
        guard let sel = selection, let l = activeLayer else { return }
        pushUndo()
        let ctx = l.context
        ctx.saveGState()
        ctx.setFillColor(UIColor(color).cgColor)
        ctx.addPath(sel)
        ctx.fillPath()
        ctx.restoreGState()
        l.markDirty()
        noteColorUsed()
        changed()
    }

    func cropToSelection() {
        guard let sel = selection else { return }
        crop(to: sel.boundingBoxOfPath)
    }

    // MARK: - Move

    func translateActiveLayer(by d: CGPoint) {
        guard let l = activeLayer, d != .zero else { return }
        pushUndo()
        let img = l.image
        l.context.clear(l.docRect)
        l.drawImage(img, in: l.docRect.offsetBy(dx: d.x, dy: d.y))
        l.markDirty()
        changed()
    }

    // MARK: - Crop

    func resetCrop() {
        cropRatio = .free
        cropRect = docRect
    }

    private func applyRatio() {
        guard hasDocument else { return }
        let W = CGFloat(docWidth), H = CGFloat(docHeight)
        guard let ratio = cropRatio.value(width: W, height: H) else { return }
        var w = W
        var h = w / ratio
        if h > H {
            h = H
            w = h * ratio
        }
        cropRect = CGRect(x: (W - w) / 2, y: (H - h) / 2, width: w, height: h)
    }

    func applyCrop() {
        crop(to: cropRect)
        tool = previousPaintTool
    }

    private func crop(to rect: CGRect) {
        let r = rect.integral.intersection(docRect)
        guard !r.isNull, r.width >= 1, r.height >= 1, r != docRect else { return }
        pushUndo()
        let w = Int(r.width), h = Int(r.height)
        layers = layers.map { old in
            let nl = PaintLayer(id: old.id, name: old.name, width: w, height: h)
            nl.isVisible = old.isVisible
            nl.opacity = old.opacity
            nl.drawImage(old.image, in: CGRect(x: -r.minX, y: -r.minY, width: CGFloat(old.width), height: CGFloat(old.height)))
            nl.markDirty()
            return nl
        }
        docWidth = w
        docHeight = h
        selection = nil
        pendingPoints = []
        cropRect = docRect
        changed()
    }

    // MARK: - Sharpen

    func openSharpen() {
        guard hasDocument else { return }
        if panel == .sharpen { cancelSharpen(); return }
        pendingPoints = []
        panel = .sharpen
        scheduleSharpenPreview()
    }

    func scheduleSharpenPreview() {
        sharpenTask?.cancel()
        guard panel == .sharpen, let l = activeLayer else { return }
        let img = Unchecked(l.image)
        let clip = Unchecked(selection)
        let radius = sharpenRadius, amount = sharpenAmount
        let id = l.id
        sharpenTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            if Task.isCancelled { return }
            let result = await Task.detached(priority: .userInitiated) { () -> Unchecked<CGImage?> in
                Unchecked(ImageOps.sharpen(img.value, radius: radius, amount: amount, clip: clip.value))
            }.value
            guard !Task.isCancelled, let self, self.panel == .sharpen, let image = result.value else { return }
            self.preview = LayerPreview(layerID: id, image: image)
            self.canvas?.setNeedsSync()
        }
    }

    func applySharpen() {
        guard let l = activeLayer else { return }
        sharpenTask?.cancel()
        let ready = (preview?.layerID == l.id) ? preview?.image : nil
        guard let result = ready ?? ImageOps.sharpen(l.image, radius: sharpenRadius, amount: sharpenAmount, clip: selection) else {
            cancelSharpen()
            return
        }
        pushUndo()
        l.replace(with: result)
        preview = nil
        panel = .none
        changed()
    }

    func cancelSharpen() {
        sharpenTask?.cancel()
        preview = nil
        panel = .none
        canvas?.setNeedsSync()
    }

    // MARK: - Content-aware fill

    func contentAwareFill() {
        guard let l = activeLayer, let sel = selection else { return }
        let buffer = l.rgbaBuffer()
        let mask = ImageOps.rasterize(sel, width: l.width, height: l.height)
        let layerID = l.id
        let width = l.width, height = l.height
        busyMessage = "Remplissage intelligent…"
        busyProgress = 0
        let model = self
        let report: @Sendable (Double) -> Void = { p in
            Task { @MainActor in
                if model.busyMessage != nil { model.busyProgress = p }
            }
        }
        Task {
            let out = await Task.detached(priority: .userInitiated) {
                Inpainter.inpaint(buffer, mask: mask, progress: report)
            }.value
            self.busyMessage = nil
            self.busyProgress = nil
            guard let layer = self.layers.first(where: { $0.id == layerID }),
                  layer.width == width, layer.height == height else { return }
            self.pushUndo()
            layer.write(out)
            self.changed()
        }
    }

    // MARK: - Export

    func flattened(opaque: Bool) -> CGImage {
        let ctx = PaintLayer.makeContext(width: docWidth, height: docHeight)
        if opaque {
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fill(docRect)
        }
        for l in layers where l.isVisible {
            ctx.saveGState()
            ctx.setAlpha(CGFloat(l.opacity))
            PaintLayer.draw(l.image, in: docRect, context: ctx)
            ctx.restoreGState()
        }
        return ctx.makeImage()!
    }

    func export(_ kind: ExportKind) {
        guard hasDocument else { return }
        if kind == .clipboard {
            UIPasteboard.general.image = UIImage(cgImage: flattened(opaque: false))
            showToast("Image copiée")
            return
        }
        busyMessage = "Export…"
        busyProgress = nil
        var datas: [Data] = []
        switch kind {
        case .jpeg:
            if let d = ImageOps.jpegData(flattened(opaque: true)) { datas = [d] }
        case .png:
            if let d = ImageOps.pngData(flattened(opaque: false)) { datas = [d] }
        case .activeLayer:
            if let img = activeLayer?.trimmedImage(), let d = ImageOps.pngData(img) { datas = [d] }
        case .eachLayer:
            datas = layers.compactMap { $0.trimmedImage() }.compactMap { ImageOps.pngData($0) }
        case .clipboard:
            break
        }
        guard !datas.isEmpty else {
            busyMessage = nil
            showToast("Rien à exporter")
            return
        }
        let payload = datas
        let count = payload.count
        Task {
            do {
                try await PhotoSaver.save(payload)
                busyMessage = nil
                showToast(count > 1 ? "\(count) images enregistrées dans Photos" : "Enregistré dans Photos")
            } catch PhotoSaver.SaveError.denied {
                busyMessage = nil
                showToast("Accès à Photos refusé — autorisez-le dans Réglages")
            } catch {
                busyMessage = nil
                showToast("Échec de l'export")
            }
        }
    }

    func share() {
        guard hasDocument, let data = ImageOps.pngData(flattened(opaque: false)) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Atelier-\(Int(Date().timeIntervalSince1970)).png")
        do {
            try data.write(to: url)
            shareItem = ShareItem(url: url)
        } catch {
            showToast("Impossible de préparer le partage")
        }
    }
}
