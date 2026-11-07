import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject private var model = EditorModel()

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.115), Color(white: 0.065)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            CanvasRepresentable(model: model)
                .ignoresSafeArea()

            if model.hasDocument {
                EditorChrome()
            } else {
                EmptyStateView()
            }

            if let message = model.busyMessage {
                BusyOverlay(message: message, progress: model.busyProgress)
                    .transition(.opacity)
            }

            if let toast = model.toast {
                VStack {
                    Text(toast)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .glassCapsule()
                    Spacer()
                }
                .padding(.top, 74)
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

// MARK: - Editor chrome

struct EditorChrome: View {
    @EnvironmentObject var model: EditorModel

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TopBar()
                Spacer(minLength: 0)
                ContextBar()
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 14)

            HStack {
                ToolPalette()
                Spacer(minLength: 0)
            }
            .padding(.leading, 16)

            if model.showLayers {
                HStack {
                    Spacer(minLength: 0)
                    VStack {
                        LayersPanel()
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 78)
                    .padding(.bottom, 110)
                }
                .padding(.trailing, 16)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.showLayers)
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    @EnvironmentObject var model: EditorModel
    @State private var item: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.accent, Color(red: 0.95, green: 0.45, blue: 0.3)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 104, height: 104)
                    .shadow(color: Theme.accent.opacity(0.35), radius: 24, y: 10)
                Image(systemName: "scissors")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.8))
            }

            VStack(spacing: 8) {
                Text("Atelier")
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                Text("Importez une photo pour la découper, la retoucher et l'exporter.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            PhotosPicker(selection: $item, matching: .images, photoLibrary: .shared()) {
                Label("Choisir une photo", systemImage: "photo.on.rectangle.angled")
                    .font(.headline)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 15)
                    .background(Capsule().fill(Theme.accent))
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)

            Button {
                model.pasteFromClipboard(asLayer: false)
            } label: {
                Label("Coller depuis le presse-papiers", systemImage: "doc.on.clipboard")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(40)
        .onChange(of: item) { newItem in
            guard let newItem else { return }
            model.load(item: newItem, asLayer: false)
            item = nil
        }
    }
}

// MARK: - Busy overlay

struct BusyOverlay: View {
    let message: String
    let progress: Double?

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                if let progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(width: 200)
                    Text("\(Int(progress * 100)) %")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.large)
                }
                Text(message)
                    .font(.headline)
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 26)
            .glass(24)
        }
    }
}
