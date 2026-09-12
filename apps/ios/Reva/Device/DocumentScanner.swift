import SwiftUI
import VisionKit

struct DocumentScanner: UIViewControllerRepresentable {
    var onFinish: ([UIImage]) -> Void
    var onCancel: () -> Void
    var onError: (Error) -> Void

    static var isSupported: Bool {
        #if targetEnvironment(simulator)
        // Some SDK/runtime combinations return true despite no document-camera input.
        return false
        #else
        return VNDocumentCameraViewController.isSupported
        #endif
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        // The presenting view must gate this with isSupported and provide a Files/sample fallback.
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
        var parent: DocumentScanner
        private var completed = false

        init(parent: DocumentScanner) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            guard !completed else { return }
            completed = true
            guard scan.pageCount > 0 else { parent.onError(DocumentImportError.invalidImage); return }
            guard scan.pageCount <= DocumentImportService.maximumPages else {
                parent.onError(DocumentImportError.tooManyPages)
                return
            }
            parent.onFinish((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            guard !completed else { return }
            completed = true
            parent.onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            guard !completed else { return }
            completed = true
            parent.onError(error)
        }
    }
}
