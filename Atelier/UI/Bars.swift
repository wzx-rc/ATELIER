import SwiftUI
import PhotosUI

// MARK: - Shared controls

struct IconButton: View {
    let icon: String
    var active = false
    var size: CGFloat = 40
    var iconSize: CGFloat = 17
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .regular))
                .frame(width: size, height: size)
                .foregroundStyle(active ? Theme.accentText : (disabled ? Theme.disabled : Theme.textSecondary))
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(active ? Theme.accentTint : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .animation(.easeOut(duration: 0.15), value: active)
    }
}

struct ActionChip: View {
    let title: String
    let icon: String
    var prominent = false
    var bordered = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: prominent ? .bold : .medium))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .foregroundStyle(prominent ? Theme.onAccent : Theme.text)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(prominent ? Theme.accent : (bordered ? Theme.control : Color.clear)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder((bordered && !prominent) ? Theme.border : Color.clear, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Petite case affichant une valeur (« 48 px », « 80 % »).
struct ValueBox: View {
    let text: String
    var width: CGFloat? = 60

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundStyle(Theme.text)
            .lineLimit(1)
            .padding(.horizontal, width == nil ? 9 : 0)
            .frame(width: width, height: 26)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.field))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }
}

/// Ligne « libellé · curseur · valeur » du panneau Propriétés.
struct PropertySlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let display: (Double) -> String
    var onEditing: (Bool) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 64, alignment: .leading)
            Slider(value: $value, in: range, onEditingChanged: onEditing)
            ValueBox(text: display(value))
        }
    }
}

struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
        }
        .toggleStyle(SwitchToggleStyle(tint: Theme.accent))
    }
}

/// Contrôle segmenté maison (texte ou icônes), dans le style V4.
struct SegmentedControl<T: Hashable>: View {
    let items: [T]
    @Binding var selection: T
    let title: (T) -> String
    var icon: ((T) -> String)? = nil

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                segment(item)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.field))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.softDivider, lineWidth: 1))
    }

    @ViewBuilder
    private func segment(_ item: T) -> some View {
        let on = item == selection
        Button {
            selection = item
        } label: {
            Group {
                if let icon {
                    Image(systemName: icon(item))
                        .font(.system(size: 16))
                } else {
                    Text(title(item))
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .foregroundStyle(on ? (icon != nil ? Theme.accentText : Color.white) : Theme.textSecondary)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? Theme.border : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title(item))
    }
}

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.textMuted)
    }
}

extension EditorModel {
    var activeToolTitle: String { panel == .sharpen ? "Netteté" : tool.title }

    var toolHint: String {
        if panel == .sharpen { return "Aperçu en direct · limité à la sélection si elle existe" }
        switch tool {
        case .brush: return fingerDraws ? "Glisser pour peindre · pincer pour zoomer" : "Le Pencil peint, le doigt navigue · double-tap Pencil : gomme"
        case .eraser: return "Double-tap Pencil : retour au pinceau"
        case .eyedropper: return "Glisser sur l'image pour prélever une couleur"
        case .select: return selectionShape.hint
        case .move: return "Glisser pour déplacer le calque actif"
        case .crop: return "Glisser les poignées pour cadrer"
        }
    }
}

// MARK: - Top bar

struct TopBar: View {
    @EnvironmentObject var model: EditorModel
    @State private var openItem: PhotosPickerItem?

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                AppMark(size: 20)
                Text("Atelier")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.text)
            }
            .padding(.trailing, 4)

            PhotosPicker(selection: $openItem, matching: .images, photoLibrary: .shared()) {
                Label("Ouvrir", systemImage: "photo.on.rectangle.angled")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .foregroundStyle(Theme.text)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.control))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Rectangle().fill(Theme.softDivider).frame(width: 1, height: 22)

            Text(model.activeToolTitle)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.text)
                .fixedSize()

            ViewThatFits(in: .horizontal) {
                ToolChips()
                Color.clear.frame(width: 1, height: 1)
            }

            Spacer(minLength: 8)

            // Toujours accessible, quel que soit l'outil, dès qu'une sélection existe.
            if model.selection != nil || !model.pendingPoints.isEmpty {
                ActionChip(title: "Désélectionner", icon: "xmark.circle", bordered: true) {
                    model.pendingPoints = []
                    model.deselect()
                }
                .transition(.opacity)
            }

            HStack(spacing: 2) {
                IconButton(icon: "arrow.uturn.backward", size: 34, disabled: !model.canUndo) { model.undo() }
                    .accessibilityLabel("Annuler")
                IconButton(icon: "arrow.uturn.forward", size: 34, disabled: !model.canRedo) { model.redo() }
                    .accessibilityLabel("Rétablir")
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.field))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.softDivider, lineWidth: 1))

            IconButton(icon: model.fingerDraws ? "hand.draw" : "hand.raised", active: !model.fingerDraws, size: 38) {
                model.fingerDraws.toggle()
                model.showToast(model.fingerDraws ? "Le doigt dessine" : "Le doigt navigue · l'Apple Pencil dessine")
            }
            .accessibilityLabel("Le doigt navigue, le Pencil dessine")

            IconButton(icon: "arrow.up.left.and.arrow.down.right", size: 38) { model.canvas?.fitToScreen() }
                .accessibilityLabel("Ajuster la vue")

            IconButton(icon: "sidebar.right", active: model.showLayers, size: 38) { model.showLayers.toggle() }
                .accessibilityLabel("Panneaux")

            ExportMenu()
        }
        .padding(.horizontal, 12)
        .frame(height: Theme.topBarHeight)
        .background(Theme.bar.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
        .onChange(of: openItem) { item in
            guard let item else { return }
            model.load(item: item, asLayer: false)
            openItem = nil
        }
    }
}

/// Réglages rapides de l'outil actif, en lecture, dans la barre du haut.
struct ToolChips: View {
    @EnvironmentObject var model: EditorModel

    private struct Chip: Identifiable {
        let id: String
        let value: String
    }

    private var chips: [Chip] {
        if model.panel == .sharpen {
            return [Chip(id: "Rayon", value: String(format: "%.1f px", model.sharpenRadius)),
                    Chip(id: "Intensité", value: String(format: "%.2f", model.sharpenAmount))]
        }
        switch model.tool {
        case .brush, .eraser:
            let s = model.tool == .eraser ? model.eraser : model.brush
            return [Chip(id: "Taille", value: "\(Int(s.size.rounded())) px"),
                    Chip(id: "Opacité", value: "\(Int((s.opacity * 100).rounded())) %"),
                    Chip(id: "Dureté", value: "\(Int((s.hardness * 100).rounded())) %")]
        case .select:
            return [Chip(id: "Forme", value: model.selectionShape.title),
                    Chip(id: "Mode", value: model.combine.title)]
        case .crop:
            return [Chip(id: "Format", value: model.cropRatio.title)]
        case .eyedropper, .move:
            return []
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(chips) { c in
                HStack(spacing: 7) {
                    Text(c.id)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textSecondary)
                    ValueBox(text: c.value, width: nil)
                }
            }
        }
        .fixedSize()
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
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, 14)
                .frame(height: 34)
                .foregroundStyle(Theme.onAccent)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.accent))
        }
    }
}

// MARK: - Document strip

struct DocumentStrip: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            HStack(spacing: 10) {
                Text("Image")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("\(model.docWidth) × \(model.docHeight) px · \(model.zoomPercent) %")
                    .font(.system(size: 12.5).monospacedDigit())
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(TopRoundedRect(radius: 8).fill(Theme.workspace))
            .overlay(TopRoundedRect(radius: 8).stroke(Theme.divider, lineWidth: 1))
            Spacer(minLength: 0)
        }
        .padding(.leading, Theme.railWidth + 12)
        .padding(.trailing, 12)
        .frame(height: Theme.documentStripHeight, alignment: .bottom)
        .background(Color(hex: 0x171C21))
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }
}

// MARK: - Tool rail

struct ToolRail: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Tool.allCases) { t in
                IconButton(icon: t.icon, active: model.tool == t && model.panel == .none, size: 40, iconSize: 18) {
                    if model.panel != .none { model.cancelSharpen() }
                    model.tool = t
                }
                .accessibilityLabel(t.title)
            }
            IconButton(icon: "wand.and.rays", active: model.panel == .sharpen, size: 40, iconSize: 18) {
                model.openSharpen()
            }
            .accessibilityLabel("Netteté")

            Spacer(minLength: 8)

            Button {
                model.showLayers = true
                model.sideTab = .swatches
            } label: {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(model.color)
                    .frame(width: 26, height: 26)
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.disabled, lineWidth: 1))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Couleur du pinceau")
        }
        .padding(.vertical, 8)
        .frame(width: Theme.railWidth)
        .frame(maxHeight: .infinity)
        .background(Theme.bar)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.divider).frame(width: 1) }
    }
}

// MARK: - Status bar

struct StatusBar: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        HStack(spacing: 18) {
            Text("\(model.zoomPercent) %")
            Text("\(model.docWidth) × \(model.docHeight) px")
            Text("Calque : \(model.activeLayer?.name ?? "—")")
            Spacer(minLength: 12)
            Text(model.toolHint)
        }
        .font(.system(size: 11.5).monospacedDigit())
        .foregroundStyle(Theme.textMuted)
        .lineLimit(1)
        .padding(.horizontal, 14)
        .frame(height: Theme.statusBarHeight)
        .background(Theme.bar.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }
}

// MARK: - Selection action bar (flotte en bas de la zone de travail)

struct SelectionActionBar: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            actions
                .padding(4)
            ScrollView(.horizontal, showsIndicators: false) {
                actions
                    .padding(4)
            }
        }
        .glass(14)
    }

    private var actions: some View {
        HStack(spacing: 2) {
            if !model.pendingPoints.isEmpty {
                ActionChip(title: "Retirer le point", icon: "arrow.uturn.backward") { model.removeLastPoint() }
                ActionChip(title: "Annuler", icon: "xmark") { model.pendingPoints = [] }
                ActionChip(title: "Fermer la forme", icon: "checkmark", prominent: true) { model.closePendingPoints() }
                    .disabled(model.pendingPoints.count < 3)
                    .opacity(model.pendingPoints.count < 3 ? 0.4 : 1)
            } else if model.selection != nil {
                ActionChip(title: "Remplissage intelligent", icon: "wand.and.stars", prominent: true) { model.contentAwareFill() }
                ActionChip(title: "Découper", icon: "scissors") { model.cutSelection(copy: false) }
                ActionChip(title: "Copier", icon: "doc.on.doc") { model.cutSelection(copy: true) }
                ActionChip(title: "Effacer", icon: "trash") { model.deleteSelectionContent() }
                ActionChip(title: "Remplir", icon: "drop") { model.fillSelection() }
                ActionChip(title: "Recadrer", icon: "crop") { model.cropToSelection() }
                ActionChip(title: "Inverser", icon: "circle.lefthalf.filled") { model.invertSelection() }
                ActionChip(title: "Désélect.", icon: "xmark.circle") { model.deselect() }
            } else {
                ActionChip(title: "Tout sélectionner", icon: "selection.pin.in.out") { model.selectAll() }
            }
        }
        .fixedSize()
    }
}

// MARK: - Contenu du panneau Propriétés

struct PropertiesContent: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        Group {
            if model.panel == .sharpen {
                SharpenProperties()
            } else {
                switch model.tool {
                case .brush: BrushProperties(isEraser: false)
                case .eraser: BrushProperties(isEraser: true)
                case .eyedropper: EyedropperProperties()
                case .select: SelectProperties()
                case .move: HintText(text: "Glissez sur l'image pour déplacer le calque actif.")
                case .crop: CropProperties()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HintText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.textMuted)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct BrushProperties: View {
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
        // Correspondance quadratique : réglage fin sur les petites tailles.
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
        VStack(alignment: .leading, spacing: 6) {
            PropertySlider(title: "Taille",
                           value: sizeBinding,
                           range: 0...1,
                           display: { _ in "\(Int(current.size.rounded())) px" },
                           onEditing: { model.showBrushPreview = $0; model.canvas?.setNeedsSync() })
            PropertySlider(title: "Opacité",
                           value: percent(\.opacity),
                           range: 0.05...1,
                           display: { "\(Int(($0 * 100).rounded())) %" })
            PropertySlider(title: "Dureté",
                           value: percent(\.hardness),
                           range: 0...1,
                           display: { "\(Int(($0 * 100).rounded())) %" })
            ToggleRow(title: "Pression Pencil → taille",
                      isOn: Binding(get: { current.pressureSize },
                                    set: { v in update { $0.pressureSize = v } }))
                .padding(.top, 2)
            if !isEraser {
                HStack(spacing: 8) {
                    ColorPicker("Couleur", selection: $model.color, supportsOpacity: false)
                        .labelsHidden()
                    ForEach(Array(model.recentColors.prefix(7).enumerated()), id: \.offset) { _, c in
                        Button { model.color = c } label: {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(c)
                                .frame(width: 24, height: 24)
                                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
                                .frame(width: 28, height: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)
            }
        }
    }
}

struct EyedropperProperties: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(model.color)
                .frame(width: 40, height: 40)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            HintText(text: "Glissez sur l'image pour prélever une couleur, puis relâchez : retour au pinceau.")
        }
    }
}

struct SelectProperties: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Forme")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 52, alignment: .leading)
                SegmentedControl(items: SelectionShape.allCases,
                                 selection: $model.selectionShape,
                                 title: { $0.title },
                                 icon: { $0.icon })
            }
            HStack(spacing: 10) {
                Text("Mode")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 52, alignment: .leading)
                SegmentedControl(items: SelectionCombine.allCases,
                                 selection: $model.combine,
                                 title: { $0.title })
            }
            HintText(text: model.selectionShape.hint)
                .padding(.leading, 62)
        }
    }
}

struct CropProperties: View {
    @EnvironmentObject var model: EditorModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(CropRatio.allCases) { r in
                    ratioButton(r)
                }
            }
            HStack(spacing: 8) {
                ActionChip(title: "Réinitialiser", icon: "arrow.counterclockwise", bordered: true) { model.resetCrop() }
                Spacer(minLength: 0)
                ActionChip(title: "Recadrer", icon: "checkmark", prominent: true) { model.applyCrop() }
            }
        }
    }

    @ViewBuilder
    private func ratioButton(_ r: CropRatio) -> some View {
        let on = model.cropRatio == r
        Button {
            model.cropRatio = r
        } label: {
            Text(r.title)
                .font(.system(size: 12.5, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .foregroundStyle(on ? Theme.accentText : Theme.textSecondary)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? Theme.accentTint : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(on ? Theme.accent : Theme.softDivider, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SharpenProperties: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PropertySlider(title: "Rayon",
                           value: $model.sharpenRadius,
                           range: 0.5...10,
                           display: { String(format: "%.1f px", $0) })
            PropertySlider(title: "Intensité",
                           value: $model.sharpenAmount,
                           range: 0...3,
                           display: { String(format: "%.2f", $0) })
            if model.selection != nil {
                HintText(text: "Limité à la sélection.")
            }
            HStack(spacing: 8) {
                ActionChip(title: "Annuler", icon: "xmark", bordered: true) { model.cancelSharpen() }
                Spacer(minLength: 0)
                ActionChip(title: "Appliquer", icon: "checkmark", prominent: true) { model.applySharpen() }
            }
            .padding(.top, 4)
        }
        .onChange(of: model.sharpenRadius) { _ in model.scheduleSharpenPreview() }
        .onChange(of: model.sharpenAmount) { _ in model.scheduleSharpenPreview() }
    }
}
