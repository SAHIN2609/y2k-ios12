//
//  GalleryManager.swift
//  y2k
//
//  Mirrors the shipped app's in-app gallery ("Your saved photos :)", "img_00%lld",
//  the y2k_gallery_metadata / y2k_image_counter keys) but stores files in the
//  app's Documents folder instead of relying on a Photos permission prompt.
//  Photos-library saving is offered separately, as in the original.
//

import UIKit
import Photos

final class GalleryManager {
    static let shared = GalleryManager()

    private let counterKey = "y2k_image_counter"
    private let metadataKey = "y2k_gallery_metadata"

    private var directory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("gallery", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Saves a rendered edit into the in-app gallery, returning its file URL.
    @discardableResult
    func save(_ image: UIImage, quality: CGFloat = 0.92) -> URL? {
        let defaults = UserDefaults.standard
        let counter = defaults.integer(forKey: counterKey) + 1
        defaults.set(counter, forKey: counterKey)
        let name = String(format: "img_%03lld.jpg", Int64(counter))
        let url = directory.appendingPathComponent(name)
        guard let data = image.jpegData(compressionQuality: quality) else { return nil }
        do {
            try data.write(to: url)
            var meta = defaults.array(forKey: metadataKey) as? [[String: Any]] ?? []
            meta.append(["name": name, "date": Date().timeIntervalSince1970])
            defaults.set(meta, forKey: metadataKey)
            return url
        } catch {
            print("Failed to save image: \(error)")
            return nil
        }
    }

    func images() -> [(name: String, image: UIImage)] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: directory.path) else { return [] }
        return files.filter { $0.hasSuffix(".jpg") }.sorted().reversed().compactMap { name in
            guard let img = UIImage(contentsOfFile: directory.appendingPathComponent(name).path) else { return nil }
            return (name, img)
        }
    }

    func delete(named name: String) {
        let url = directory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Photos library saving

enum PhotosSaver {
    /// The original's save flow, with its exact failure copy.
    static func save(_ image: UIImage, completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    completion(false)
                    return
                }
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }) { success, _ in
                    DispatchQueue.main.async { completion(success) }
                }
            }
        }
    }
}
