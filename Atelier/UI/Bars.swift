import SwiftUI
import PhotosUI

// MARK: - Shared controls

struct IconButton: View {
    let icon: String
    var active = false
    var size: CGFloat = 44
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .frame(width: size, height: size)
                .foregroundStyle(active ? Color.black : Color.white.opacity(disabled ? 0.3 : 0.92))
                .background {
                    if active {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accent)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: active)
    }
}

struct ActionChip: View {
    let title: String
    let icon: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .foregroundStyle(prominent ? Color.black : Color.white)
                .background(Capsule().fill(prominent ? Theme.accent : Color.white.opacity(0.09)))
        }
        .buttonStyle(.plain)
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let display: (Double) -> String
    var width: CGFloat = 150
    var onEditing: (Bool) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(display(value))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, onEditingChanged: onEditing)
        }
        .frame(width: width)
    }
}

// MARK: - Top bar

struct TopBar: View {
    @EnvironmentObject var model: EditorModel
    @State private var openItem: PhotosPickerItem?

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                PhotosPicker(selection: $openItem, matching: .images, photoLibrary: .shared()) {
                    Label("Ouvrir", systemImage: "photo.on.rectangle.angled")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(4)
            .glass(16)

            Spacer(minLength: 0)

            HStack(spacing: 2) {
                IconButton(icon: "arrow.uturn.backward", disabled: !model.canUndo) { model.undo() }
                IconButton(icon: "arrow.uturn.forward", disabled: !model.canRedo) { model.redo() }
            }
            .padding(4)
            .glass(16)

            Spacer(minLength: 0)

            HStack(spacing: 2) {
                IconButton(icon: model.fingerDraws ? "hand.draw" : "hand.raised", active: !model.fingerDraws) {
                    model.fingerDraws.toggle()
                    model.showToast(model.fingerDraws ? "Le doigt dessine" : "Le doigt navigue · l'Apple Pencil dessine")
                }
                IconButton(icon: "arrow.up.left.and.arrow.down.right") { model.canvas?.fitToScreen() }
                IconButton(icon: "square.3.layers.3d", active: model.showLayers) { model.showLayers.toggle() }
                ExportMenu()
            }
            .padding(4)
            .glass(16)
        }
        .onChange(of: openItem) { item in
            guard let item else { return }
            model.load(item: item, asLayer: false)
            openItem = nil
        }
    }
}

struct ExportMenu: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        Menu {
            Section("Enregistrer dans Photos") {
                Button { model.export(.jpeg) } label: { Label("Image (JPEG)", systemImage: "photo") }
                Button { model.export(.png) } label: { Label("Image avec transparence (PNG)", systemImage: "square.on.square.dashed") }
                Button { model.export(.activeLayer) } label: { Label("Calque actif seul", systemImage: "square.2.layers.3d.top.filled") }
                Button { model.export(.eachLayer) } label: { Label("Chaque calque séparément", systemImage: "square.3.layers.3d") }
            }
            Section {
                Button { model.export(.clipboard) } label: { Label("Copier", systemImage: "doc.on.doc") }
                Button { model.share() } label: { Label("Partager…", systemImage: "square.and.arrow.up") }
            }
        } label: {
            Label("Exporter", systemImage: "square.and.arrow.up")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(height: 40)
                .foregroundStyle(.black)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accent))
        }
        .padding(.leading, 4)
    }
}

// MARK: - Tool palette

struct ToolPalette: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Tool.allCases) { t in
                IconButton(icon: t.icon, active: model.tool == t && model.panel == .none) {
                    if model.panel != .none { model.cancelSharpen() }
                    model.tool = t
                }
                .accessibilityLabel(t.title)
            }
            Divider()
                .frame(width: 30)
                .padding(.vertical, 4)
            IconButton(icon: "wand.and.rays", active: model.panel == .sharpen) { model.openSharpen() }
                .accessibilityLabel("Netteté")
            Divider()
                .frame(width: 30)
                .padding(.vertical, 4)
            Button {
                if model.tool != .brush { model.tool = .brush }
            } label: {
                Circle()
                    .fill(model.color)
                    .frame(width: 30, height: 30)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 2))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(6)
        .glass(22)
    }
}

// MARK: - Context bar

struct ContextBar: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        Group {
            if model.panel == .sharpen {
                SharpenBar()
            } else {
                switch model.tool {
                case .brush: BrushBar(isEraser: false)
                case .eraser: BrushBar(isEraser: true)
                case .eyedropper: EyedropperBar()
                case .select: SelectBar()
                case .move: HintBar(icon: "arrow.up.and.down.and.arrow.left.and.right",
                                    text: "Glissez pour déplacer le calque actif")
                case .crop: CropBar()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glass(22)
        .padding(.leading, 70)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: model.tool)
    }
}

struct HintBar: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
    }
}

struct BrushBar: View {
    @EnvironmentObject var model: EditorModel
    let isEraser: Bool

    private var current: BrushSettings { isEraser ? model.eraser : model.brush }

    private func update(_ change: (inout BrushSettings) -> Void) {
        if isEraser {
            var s = model.eraser
            change(&s)
            model.eraser = s
        } else {
            var s = model.brush
            change(&s)
            model.brush = s
        }
    }

    private var sizeBinding: Binding<Double> {
        // Quadratic mapping: fine control on small sizes.
        Binding(
            get: { sqrt(max(0, (Double(current.size) - 1) / 399)) },
            set: { v in update { $0.size = CGFloat(1 + 399 * v * v) } }
        )
    }

    private func percent(_ kp: WritableKeyPath<BrushSettings, CGFloat>) -> Binding<Double> {
        Binding(get: { Double(current[keyPath: kp]) },
                set: { v in update { $0[keyPath: kp] = CGFloat(v) } })
    }

    var body: some View {
        HStack(spacing: 18) {
            if !isEraser {
                HStack(spacing: 8) {
                    ColorPicker("Couleur", selection: $model.color, supportsOpacity: false)
                        .labelsHidden()
                    ForEach(Array(model.recentColors.prefix(6).enumerated()), id: \.offset) { _, c in
                        Button { model.color = c } label: {
                            Circle()
                                .fill(c)
                                .frame(width: 24, height: 24)
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Divider().frame(height: 30)
            }
            LabeledSlider(title: "Taille",
                          value: sizeBinding,
                          range: 0...1,
                          display: { _ in "\(Int(current.size.rounded())) px" },
                          onEditing: { model.showBrushPreview = $0; model.canvas?.setNeedsSync() })
            LabeledSlider(title: "Opacité",
                          value: percent(\.opacity),
                          range: 0.05...1,
                          display: { "\(Int(($0 * 100).rounded())) %" })
            LabeledSlider(title: "Dureté",
                          value: percent(\.hardness),
                          range: 0...1,
                          display: { "\(Int(($0 * 100).rounded())) %" })
            IconButton(icon: "applepencil", active: current.pressureSize) {
                update { $0.pressureSize.toggle() }
            }
            .accessibilityLabel("Pression → taille")
        }
    }
}

struct EyedropperBar: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(model.color)
                .frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 2))
            Text("Touchez et glissez sur l'image pour prélever une couleur")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct SelectBar: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(SelectionShape.allCases) { s in
                    VStack(spacing: 2) {
                        IconButton(icon: s.icon, active: model.selectionShape == s, size: 40) { model.selectionShape = s }
                        Text(s.title)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(model.selectionShape == s ? Theme.accent : .secondary)
                    }
                }
                Divider().frame(height: 36).padding(.horizontal, 6)
                ForEach(SelectionCombine.allCases) { c in
                    VStack(spacing: 2) {
                        IconButton(icon: c.icon, active: model.combine == c, size: 40) { model.combine = c }
                        Text(c.title)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(model.combine == c ? Theme.accent : .secondary)
                    }
                }
                Divider().frame(height: 36).padding(.horizontal, 6)
                if model.pendingPoints.isEmpty {
                    Text(model.selectionShape.hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 230, alignment: .leading)
                        .lineLimit(2)
                } else {
                    ActionChip(title: "Retirer", icon: "arrow.uturn.backward") { model.removeLastPoint() }
                    ActionChip(title: "Annuler", icon: "xmark") { model.pendingPoints = [] }
                    ActionChip(title: "Fermer", icon: "checkmark", prominent: true) { model.closePendingPoints() }
                        .disabled(model.pendingPoints.count < 3)
                        .opacity(model.pendingPoints.count < 3 ? 0.4 : 1)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if model.selection != nil {
                        ActionChip(title: "Remplissage intelligent", icon: "wand.and.stars", prominent: true) { model.contentAwareFill() }
                        ActionChip(title: "Découper", icon: "scissors") { model.cutSelection(copy: false) }
                        ActionChip(title: "Copier", icon: "doc.on.doc") { model.cutSelection(copy: true) }
                        ActionChip(title: "Effacer", icon: "trash") { model.deleteSelectionContent() }
                        ActionChip(title: "Remplir", icon: "drop.fill") { model.fillSelection() }
                        ActionChip(title: "Recadrer", icon: "crop") { model.cropToSelection() }
                        ActionChip(title: "Inverser", icon: "circle.lefthalf.filled") { model.invertSelection() }
                        ActionChip(title: "Désélectionner", icon: "xmark.circle") { model.deselect() }
                    } else {
                        ActionChip(title: "Tout sélectionner", icon: "selection.pin.in.out") { model.selectAll() }
                    }
                }
            }
            .frame(maxWidth: 820)
        }
    }
}

struct CropBar: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        HStack(spacing: 14) {
            Picker("Format", selection: $model.cropRatio) {
                ForEach(CropRatio.allCases) { r in
                    Text(r.title).tag(r)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 400)

            ActionChip(title: "Réinitialiser", icon: "arrow.counterclockwise") { model.resetCrop() }
            ActionChip(title: "Recadrer", icon: "checkmark", prominent: true) { model.applyCrop() }
        }
    }
}

struct SharpenBar: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        HStack(spacing: 20) {
            Label("Netteté", systemImage: "wand.and.rays")
                .font(.subheadline.weight(.semibold))
            LabeledSlider(title: "Rayon",
                          value: $model.sharpenRadius,
                          range: 0.5...10,
                          display: { String(format: "%.1f px", $0) },
                          width: 170)
            LabeledSlider(title: "Intensité",
                          value: $model.sharpenAmount,
                          range: 0...3,
                          display: { String(format: "%.2f", $0) },
                          width: 170)
            if model.selection != nil {
                Text("Limité à la sélection")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ActionChip(title: "Annuler", icon: "xmark") { model.cancelSharpen() }
            ActionChip(title: "Appliquer", icon: "checkmark", prominent: true) { model.applySharpen() }
        }
        .onChange(of: model.sharpenRadius) { _ in model.scheduleSharpenPreview() }
        .onChange(of: model.sharpenAmount) { _ in model.scheduleSharpenPreview() }
    }
}
