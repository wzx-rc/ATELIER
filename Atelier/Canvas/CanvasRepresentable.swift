import SwiftUI

struct CanvasRepresentable: UIViewRepresentable {
    let model: EditorModel

    func makeUIView(context: Context) -> CanvasView {
        let view = CanvasView(model: model)
        model.canvas = view
        return view
    }

    func updateUIView(_ uiView: CanvasView, context: Context) {
        uiView.setNeedsSync()
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
