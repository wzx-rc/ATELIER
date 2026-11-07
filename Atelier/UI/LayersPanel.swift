import SwiftUI
import PhotosUI

struct LayersPanel: View {
    @EnvironmentObject var model: EditorModel
    @State private var photoItem: PhotosPickerItem?
    @State private var renamingID: UUID?
    @State private var renameText = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text("Calques")
                    .font(.headline)
                Spacer()
                PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 36, height: 36)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Importer une photo comme calque")
                IconButton(icon: "plus", size: 36) { model.addEmptyLayer() }
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .padding(.vertical, 6)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Array(model.layers.reversed())) { layer in
                        row(layer)
                    }
                }
                .padding(.horizontal, 6)
            }
            .frame(maxHeight: 330)

            if let active = model.activeLayer {
                Divider().padding(.top, 6)
                VStack(spacing: 8) {
                    LabeledSlider(title: "Opacité",
                                  value: Binding(get: { active.opacity },
                                                 set: { model.setOpacity($0, for: active.id) }),
                                  range: 0...1,
                                  display: { "\(Int(($0 * 100).rounded())) %" },
                                  width: 228)
                    HStack(spacing: 0) {
                        IconButton(icon: "chevron.up", size: 38) { model.moveActiveLayer(up: true) }
                        IconButton(icon: "chevron.down", size: 38) { model.moveActiveLayer(up: false) }
                        IconButton(icon: "plus.square.on.square", size: 38) { model.duplicateActiveLayer() }
                        IconButton(icon: "arrow.down.to.line", size: 38, disabled: model.layers.first?.id == active.id) { model.mergeDown() }
                        IconButton(icon: "trash", size: 38, disabled: model.layers.count <= 1) { model.deleteActiveLayer() }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }
        }
        .frame(width: 252)
        .glass(20)
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
            .frame(width: 46, height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isActive ? Theme.accent : Color.white.opacity(0.12), lineWidth: isActive ? 2 : 1))

            Text(layer.name)
                .font(.subheadline.weight(isActive ? .semibold : .regular))
                .lineLimit(1)
                .foregroundStyle(layer.isVisible ? .primary : .secondary)

            Spacer(minLength: 0)

            Button {
                model.toggleVisibility(layer.id)
            } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .font(.system(size: 14))
                    .foregroundStyle(layer.isVisible ? Color.white.opacity(0.85) : Color.white.opacity(0.35))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isActive ? Theme.accent.opacity(0.16) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture { model.selectLayer(layer.id) }
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
