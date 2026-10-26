import SwiftUI
import UIKit

/// The system camera; hands back the photo as JPEG data (orientation preserved in EXIF), or
/// reports that the shot couldn't be used.
struct CameraPicker: UIViewControllerRepresentable {
    var onCapture: (Data) -> Void
    var onFailure: () -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        /// The shot is being encoded or was handed over: a second Use Photo meanwhile hands nothing.
        private var isDelivering = false

        init(parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard !isDelivering else { return }
            isDelivering = true
            let image = info[.originalImage] as? UIImage
            Task {
                if let image, let data = await Self.jpeg(image) {
                    parent.onCapture(data)
                } else {
                    parent.onFailure()
                }
                parent.dismiss()
            }
        }

        /// Off the main actor: a capture is 12 to 48 megapixels, a few hundred milliseconds to encode.
        @concurrent
        private static func jpeg(_ image: UIImage) async -> Data? {
            image.jpegData(compressionQuality: 0.95)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
