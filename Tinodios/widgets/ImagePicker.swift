//
//  ImagePicker.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import MobileCoreServices
import UIKit

public enum ImagePickerMediaType {
    case image(UIImage?, String?, String?)
    case video(URL?, String?, String?)
}

public protocol ImagePickerDelegate: AnyObject {
    func didSelect(media: ImagePickerMediaType?)
}

open class ImagePicker: NSObject {

    private let pickerController: UIImagePickerController
    private let allowVideo: Bool
    private weak var presentationController: UIViewController?
    private weak var delegate: ImagePickerDelegate?

    public init(presentationController: UIViewController, delegate: ImagePickerDelegate, editable: Bool,
                allowVideo: Bool = false) {
        self.pickerController = UIImagePickerController()
        self.allowVideo = allowVideo

        super.init()

        self.presentationController = presentationController
        self.delegate = delegate

        self.pickerController.delegate = self
        self.pickerController.allowsEditing = editable
        self.pickerController.mediaTypes = [kUTTypeImage as String]
        if allowVideo {
            self.pickerController.mediaTypes.append(kUTTypeMovie as String)
        }
    }

    private func action(for type: UIImagePickerController.SourceType, title: String) -> UIAlertAction? {
        guard UIImagePickerController.isSourceTypeAvailable(type) else {
            return nil
        }

        return UIAlertAction(title: title, style: .default) { [unowned self] _ in
            self.pickerController.sourceType = type
            self.presentationController?.present(self.pickerController, animated: true)
        }
    }

    public func present(from sourceView: UIView) {

        let alertController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        let cameraTitle = allowVideo ? NSLocalizedString("Take photo or video", comment: "Camera action") :
            NSLocalizedString("Take photo", comment: "Camera action")
        if let action = self.action(for: .camera, title: cameraTitle) {
            alertController.addAction(action)
        }
        let libraryTitle = allowVideo ? NSLocalizedString("Choose photo or video", comment: "Media library action") :
            NSLocalizedString("Choose photo", comment: "Photo library action")
        if let action = self.action(for: .photoLibrary, title: libraryTitle) {
            alertController.addAction(action)
        }

        alertController.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel action"), style: .cancel, handler: nil))

        if UIDevice.current.userInterfaceIdiom == .pad {
            alertController.popoverPresentationController?.sourceView = sourceView
            alertController.popoverPresentationController?.sourceRect = sourceView.bounds
            alertController.popoverPresentationController?.permittedArrowDirections = [.down, .up]
        }

        // Unnecessary empty view is added and animation is disabled because of
        // https://stackoverflow.com/questions/55653187/swift-default-alertviewcontroller-breaking-constraints
        // https://stackoverflow.com/questions/55372093/uialertcontrollers-actionsheet-gives-constraint-error-on-ios-12-2
        // FIXME: Remove the following line and make `animation: true` when Apple fixes the bug.
        alertController.view.addSubview(UIView())
        self.presentationController?.present(alertController, animated: false)
    }

    private func pickerController(_ controller: UIImagePickerController, didSelect media: ImagePickerMediaType?) {
        controller.dismiss(animated: true, completion: nil)
        self.delegate?.didSelect(media: media)
    }

    private static func extractFileNameAndMimeType(fromURL url: NSURL?) -> (NSString?, String?) {
        guard let url = url else { return (nil, nil) }
        // Get mime type and file name
        let urlResourceValues = try? url.resourceValues(forKeys: [.typeIdentifierKey, .nameKey])
        let uti = urlResourceValues?[.typeIdentifierKey] as? NSString
        let fname = urlResourceValues?[.nameKey] as? NSString
        var mimeType: String?
        if let uti = uti {
            // Convert UTI string like 'public.jpeg' to MIME type like 'image/jpeg'
            let unmanaged = UTTypeCopyPreferredTagWithClass(uti as CFString, kUTTagClassMIMEType)
            mimeType = unmanaged?.takeRetainedValue() as String?
        } else {
            mimeType = nil
        }
        return (fname, mimeType)
    }

    private func didPickImage(_ picker: UIImagePickerController,
                              didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        guard let image = (info[self.pickerController.allowsEditing ? .editedImage : .originalImage] as? UIImage)?.fixedOrientation() else {
            return self.pickerController(picker, didSelect: nil)
        }

        var mimeType: String? = nil
        var fname: NSString? = nil
        if self.pickerController.sourceType == .camera {
            // Images taken by camera won't have .imageURL or .referenceURL.
            // Generate the file name from the timestamp and set the mime type to "image/png".
            if let metadata = info[.mediaMetadata] as? [NSString: Any], let exif = metadata["{Exif}"] as? [NSString: Any] {
                fname = ((exif["DateTimeOriginal"] as? NSString ?? "unknown").replacingOccurrences(of: " ", with: "-") + ".png") as NSString
                mimeType = "image/png"
            }
        } else {
            let imageUrl = info[.imageURL] as? NSURL

            let result = ImagePicker.extractFileNameAndMimeType(fromURL: imageUrl)
            fname = result.0
            mimeType = result.1
        }

        self.pickerController(picker, didSelect: .image(image, mimeType, fname as String?))
    }

    private func didPickVideo(_ picker: UIImagePickerController,
                              didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        // Currently UIImagePickerController compresses and converts the original video into quicktime
        // which makes the original video file name, size, format and dimensions unavailable.
        // Sometimes it may break some of these params, e.g. dimensions.
        // To be able to access the original video file, we need to use PHPickerViewController.
        // TODO: switch to PHPickerViewController.
        guard let videoUrl = info[.mediaURL] as? NSURL else {
            return self.pickerController(picker, didSelect: nil)
        }
        let result = ImagePicker.extractFileNameAndMimeType(fromURL: videoUrl)
        let swiftUrl = videoUrl as URL
        let fname = result.0 as String? ?? (swiftUrl.lastPathComponent.isEmpty ? "claw_os_video.mov" : swiftUrl.lastPathComponent)
        let mimeType = result.1 ?? Utils.mimeForUrl(url: swiftUrl, ifMissing: "video/quicktime")

        self.pickerController(picker, didSelect: .video(swiftUrl, mimeType, fname))
    }
}

extension ImagePicker: UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        self.pickerController(picker, didSelect: nil/*, mimeType: nil, fileName: nil*/)
        picker.dismiss(animated: true, completion: nil)
    }

    public func imagePickerController(_ picker: UIImagePickerController,
                                      didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        guard !picker.isBeingDismissed else {
            // Prevent ImagePicker from showing the image multiple times.
            return
        }
        guard let mediaType = info[.mediaType] as? String else {
            return self.pickerController(picker, didSelect: nil)
        }
        switch mediaType as CFString {
        case kUTTypeImage:
            didPickImage(picker, didFinishPickingMediaWithInfo: info)
            break
        case kUTTypeMovie:
            didPickVideo(picker, didFinishPickingMediaWithInfo: info)
            break
        default:
            return self.pickerController(picker, didSelect: nil/*, mimeType: nil, fileName: nil*/)
        }
    }
}
