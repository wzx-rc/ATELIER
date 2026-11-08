import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject private var model = EditorModel()

    var body: some View {
        ZStack {
            Theme.workspace.ignoresSafeArea()

            if model.hasDocument {
                EditorLayout()
            } else {
                WelcomeView()
            }

            if let message = model.busyMessage {
                BusyOverlay(message: message, progress: model.busyProgress)
                    .transition(.opacity)
            }

            if let toast = model.toast {
                VStack {
                    Text(toast)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassCapsule()
                    Spacer()
                }
                .padding(.top, Theme.topBarHeight + Theme.documentStripHeight + 14)
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.toast)
        .animation(.easeInOut(duration: 0.2), value: model.busyMessage)
        .environmentObject(model)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .sheet(item: $model.shareItem) { item in
            ShareSheet(items: [item.url])
        }
    }
}

// MARK: - Éditeur : barres et panneaux ancrés autour de la zone de travail

struct EditorLayout: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            DocumentStrip()
            HStack(spacing: 0) {
                ToolRail()
                ZStack(alignment: .bottom) {
                    Theme.workspace
                    // Le canvas n'occupe que la zone centrale : il se recadre tout seul
                    // quand le panneau latéral s'ouvre ou se ferme.
                    CanvasRepresentable(model: model)
                    if model.tool == .select && model.panel == .none {
                        SelectionActionBar()
                            .padding(.horizontal, 14)
                            .padding(.bottom, 14)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .clipped()
                if model.showLayers {
                    SidePanel()
                        .transition(.move(edge: .trailing))
                }
            }
            StatusBar()
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: model.showLayers)
        .animation(.easeOut(duration: 0.2), value: model.tool)
    }
}

// MARK: - Accueil

struct WelcomeView: View {
    @EnvironmentObject var model: EditorModel
    @State private var item: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                AppMark(size: 20)
                Text("Atelier")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.text)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: Theme.topBarHeight)
            .background(Theme.bar.ignoresSafeArea(edges: .top))
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        AppMark(size: 30, lineWidth: 1.3)
                            .frame(width: 48, height: 48)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.workspace))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.softDivider, lineWidth: 1))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Atelier")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Theme.text)
                            Text("Retouche simple pour iPad")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                    .padding(.bottom, 16)

                    PhotosPicker(selection: $item, matching: .images, photoLibrary: .shared()) {
                        Label("Choisir une photo", systemImage: "photo.on.rectangle.angled")
                            .font(.system(size: 14, weight: .bold))
                            .padding(.horizontal, 14)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .foregroundStyle(Theme.onAccent)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accent))
                    }
                    .buttonStyle(.plain)

                    Button {
                        model.pasteFromClipboard(asLayer: false)
                    } label: {
                        Label("Coller depuis le presse-papiers", systemImage: "doc.on.clipboard")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 14)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .foregroundStyle(Theme.text)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.control))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 16)

                    Text("Astuce : avec l'Apple Pencil, touchez deux fois le crayon pour passer du pinceau à la gomme.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 28)
                .frame(width: 300)
                .frame(maxHeight: .infinity)
                .background(Theme.raised)
                .overlay(alignment: .trailing) { Rectangle().fill(Theme.softDivider).frame(width: 1) }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Ce que vous pouvez faire")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.text)
                    FeatureRow(icon: "lasso", title: "Découper", text: "Points, courbe, lasso, rectangle ou ellipse, puis découpe sur un nouveau calque.")
                    FeatureRow(icon: "paintbrush.pointed", title: "Peindre", text: "Pinceau et gomme sensibles à la pression, pipette.")
                    FeatureRow(icon: "wand.and.stars", title: "Remplissage intelligent", text: "Bouche les trous et efface des éléments de la photo.")
                    FeatureRow(icon: "crop", title: "Recadrer et netteté", text: "Formats prédéfinis, grille des tiers, accentuation.")
                    FeatureRow(icon: "square.and.arrow.up", title: "Exporter", text: "Directement dans Photos, en JPEG ou PNG, calque par calque si besoin.")
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: 820)
            .frame(height: 420)
            .background(Theme.bar)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.softDivider, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 28, x: 0, y: 20)
            .padding(24)

            Spacer(minLength: 0)
        }
        .onChange(of: item) { newItem in
            guard let newItem else { return }
            model.load(item: newItem, asLayer: false)
            item = nil
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Theme.accentText)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.accentTint))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Busy overlay

struct BusyOverlay: View {
    let message: String
    let progress: Double?

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 14) {
                if let progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(width: 220)
                    Text("\(Int(progress * 100)) %")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(Theme.textMuted)
                } else {
                    ProgressView()
                        .controlSize(.large)
                }
                Text(message)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 26)
            .glass(16)
        }
    }
}
