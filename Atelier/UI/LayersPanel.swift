import SwiftUI
import PhotosUI

// MARK: - Panneau latéral ancré à droite (Navigateur, Propriétés, Calques / Nuancier)

struct SidePanel: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        VStack(spacing: 0) {
            NavigatorSection()
            PanelDivider()

            PanelHeader {
                PanelTab(title: "Propriétés", selected: true)
                Spacer(minLength: 8)
                Text(model.activeToolTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted)
            }
            PropertiesContent()
                .padding(.horizontal, 14)
                .padding(.top, 4)
                .padding(.bottom, 14)
            PanelDivider()

            PanelHeader {
                ForEach(SideTab.allCases) { tab in
                    PanelTab(title: tab.title, selected: model.sideTab == tab) { model.sideTab = tab }
                }
                Spacer(minLength: 0)
            }
            Group {
                switch model.sideTab {
                case .layers: LayersSection()
                case .swatches: SwatchesSection()
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(width: Theme.sidePanelWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.bar)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.divider).frame(width: 1) }
    }
}

struct PanelDivider: View {
    var body: some View {
        Rectangle().fill(Theme.divider).frame(height: 1)
    }
}

struct PanelHeader<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 16) {
            content()
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
    }
}

struct PanelTab: View {
    let title: String
    let selected: Bool
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(selected ? Theme.text : Theme.textMuted)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(selected ? Theme.accent : Color.clear)
                        .frame(height: 2)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Navigateur

struct NavigatorSection: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader {
                PanelTab(title: "Navigateur", selected: true) {
                    withAnimation(.easeInOut(duration: 0.2)) { model.navigatorExpanded.toggle() }
                }
                Spacer(minLength: 0)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { model.navigatorExpanded.toggle() }
                } label: {
                    Image(systemName: model.navigatorExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.navigatorExpanded ? "Replier le navigateur" : "Déplier le navigateur")
            }

            if model.navigatorExpanded {
                VStack(spacing: 8) {
                    NavigatorThumbnail()
                        .frame(height: 124)
                    HStack(spacing: 10) {
                        Text("Zoom")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer(minLength: 0)
                        ValueBox(text: "\(model.zoomPercent) %")
                        IconButton(icon: "arrow.up.left.and.arrow.down.right", size: 32, iconSize: 14) {
                            model.canvas?.fitToScreen()
                        }
                        .accessibilityLabel("Ajuster la vue")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .transition(.opacity)
            }
        }
    }
}

struct NavigatorThumbnail: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        GeometryReader { geo in
            let docW = CGFloat(max(1, model.docWidth))
            let docH = CGFloat(max(1, model.docHeight))
            let s = min(geo.size.width / docW, geo.size.height / docH)
            let vp = model.viewport
            ZStack(alignment: .topLeading) {
                Image(uiImage: CheckerPattern.image)
                    .resizable(resizingMode: .tile)
                ForEach(model.layers) { layer in
                    if layer.isVisible, let thumb = layer.thumbnail {
                        Image(decorative: thumb, scale: 1)
                            .resizable()
                            .interpolation(.medium)
                            .opacity(layer.opacity)
                    }
                }
                if vp.width > 0 && vp.height > 0 {
                    Rectangle()
                        .strokeBorder(Theme.accent, lineWidth: 1.5)
                        .frame(width: max(6, vp.width * s), height: max(6, vp.height * s))
                        .offset(x: vp.minX * s, y: vp.minY * s)
                }
            }
            .frame(width: docW * s, height: docH * s)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Calques

struct LayersSection: View {
    @EnvironmentObject var model: EditorModel
    @State private var photoItem: PhotosPickerItem?
    @State private var renamingID: UUID?
    @State private var renameText = ""

    var body: some View {
        VStack(spacing: 0) {
            if let active = model.activeLayer {
                PropertySlider(title: "Opacité",
                               value: Binding(get: { active.opacity },
                                              set: { model.setOpacity($0, for: active.id) }),
                               range: 0...1,
                               display: { "\(Int(($0 * 100).rounded())) %" })
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(model.layers.reversed())) { layer in
                        row(layer)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 0) {
                PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 38, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Importer une photo comme calque")
                IconButton(icon: "plus", size: 38, iconSize: 16) { model.addEmptyLayer() }
                    .accessibilityLabel("Nouveau calque")
                IconButton(icon: "plus.square.on.square", size: 38, iconSize: 16) { model.duplicateActiveLayer() }
                    .accessibilityLabel("Dupliquer")
                IconButton(icon: "arrow.down.to.line", size: 38, iconSize: 16,
                           disabled: model.layers.first?.id == model.activeLayer?.id) { model.mergeDown() }
                    .accessibilityLabel("Fusionner vers le bas")
                IconButton(icon: "chevron.up", size: 38, iconSize: 16) { model.moveActiveLayer(up: true) }
                    .accessibilityLabel("Monter")
                IconButton(icon: "chevron.down", size: 38, iconSize: 16) { model.moveActiveLayer(up: false) }
                    .accessibilityLabel("Descendre")
                IconButton(icon: "trash", size: 38, iconSize: 16, disabled: model.layers.count <= 1) { model.deleteActiveLayer() }
                    .accessibilityLabel("Supprimer")
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .overlay(alignment: .top) { Rectangle().fill(Theme.divider).frame(height: 1) }
        }
        .onChange(of: photoItem) { item in
            guard let item else { return }
            model.load(item: item, asLayer: true)
            photoItem = nil
        }
        .alert("Renommer le calque", isPresented: Binding(get: { renamingID != nil },
                                                          set: { if !$0 { renamingID = nil } })) {
            TextField("Nom", text: $renameText)
            Button("Annuler", role: .cancel) { renamingID = nil }
            Button("OK") {
                if let id = renamingID { model.rename(id, to: renameText) }
                renamingID = nil
            }
        }
    }

    @ViewBuilder
    private func row(_ layer: PaintLayer) -> some View {
        let isActive = model.activeLayer?.id == layer.id
        HStack(spacing: 0) {
            Button {
                model.toggleVisibility(layer.id)
            } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .font(.system(size: 14))
                    .foregroundStyle(layer.isVisible ? Theme.text : Theme.disabled)
                    .frame(width: 38, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(layer.isVisible ? "Masquer \(layer.name)" : "Afficher \(layer.name)")

            HStack(spacing: 10) {
                ZStack {
                    Image(uiImage: CheckerPattern.image)
                        .resizable(resizingMode: .tile)
                    if let thumb = layer.thumbnail {
                        Image(decorative: thumb, scale: 1)
                            .resizable()
                            .interpolation(.medium)
                            .aspectRatio(contentMode: .fit)
                    }
                }
                .frame(width: 42, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isActive ? Theme.accent : Theme.border, lineWidth: 1))

                VStack(alignment: .leading, spacing: 1) {
                    Text(layer.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isActive ? Theme.accentText : (layer.isVisible ? Theme.text : Theme.textMuted))
                        .lineLimit(1)
                    Text("\(Int((layer.opacity * 100).rounded())) %")
                        .font(.system(size: 11.5).monospacedDigit())
                        .foregroundStyle(Theme.textMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(.trailing, 10)
            .frame(height: 48)
            .contentShape(Rectangle())
            .onTapGesture { model.selectLayer(layer.id) }
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isActive ? Theme.accentTint : Color.clear))
        .contextMenu {
            Button {
                renameText = layer.name
                renamingID = layer.id
            } label: { Label("Renommer", systemImage: "pencil") }
            Button {
                model.selectLayer(layer.id)
                model.duplicateActiveLayer()
            } label: { Label("Dupliquer", systemImage: "plus.square.on.square") }
            Button {
                model.selectLayer(layer.id)
                model.export(.activeLayer)
            } label: { Label("Enregistrer dans Photos", systemImage: "square.and.arrow.down") }
            if model.layers.count > 1 {
                Button(role: .destructive) {
                    model.selectLayer(layer.id)
                    model.deleteActiveLayer()
                } label: { Label("Supprimer", systemImage: "trash") }
            }
        }
    }
}

// MARK: - Nuancier

struct SwatchesSection: View {
    @EnvironmentObject var model: EditorModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

    private let palette: [Color] = [
        .white, Color(hex: 0xA9B5BD), Color(hex: 0x5C6A74), Color(hex: 0x2C353D), .black, Color(hex: 0x3FC1D9),
        Color(hex: 0xD94F4F), Color(hex: 0xE8833A), Color(hex: 0xF2C94C), Color(hex: 0x6FBF73), Color(hex: 0x3B82C4), Color(hex: 0x7C5CD6),
        Color(hex: 0xD45D9E), Color(hex: 0x8A5A3C), Color(hex: 0xFFE7D8), Color(hex: 0xF29A6A), Color(hex: 0xB8407A), Color(hex: 0x1B3A4D)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(model.color)
                        .frame(width: 40, height: 40)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
                    Text("Couleur du pinceau")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 0)
                    ColorPicker("Choisir une couleur", selection: $model.color, supportsOpacity: false)
                        .labelsHidden()
                }

                if !model.recentColors.isEmpty {
                    SectionLabel(text: "Récentes")
                    grid(Array(model.recentColors.prefix(12)))
                }

                SectionLabel(text: "Palette")
                grid(palette)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }

    private func grid(_ colors: [Color]) -> some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, c in
                Button {
                    model.color = c
                } label: {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(c)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
