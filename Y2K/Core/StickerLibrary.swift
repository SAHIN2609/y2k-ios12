//
//  StickerLibrary.swift
//  y2k
//
//  Sticker folders + the sticker strip. The original syncs its sticker CDN from
//  Firebase Storage (bucket y2k-app.firebasestorage.app) and caches the result
//  on disk with fallback bookkeeping ("sticker_cdn_use_fallback",
//  "Showing cached stickers"). That CDN is not reachable from a clone, so this
//  reads the bundled Stickers/ folder instead and keeps the same
//  "Black", "White", … folder taxonomy from the original's tutorial copy.
//

import UIKit

struct StickerFolder {
    let name: String            // localised folder label, e.g. "Black"
    let directory: String       // bundle subfolder
    let stickers: [String]      // image names without extension
}

final class StickerLibrary {
    static let shared = StickerLibrary()

    /// Folder order follows the original tutorial, which starts at "Black".
    private(set) lazy var folders: [StickerFolder] = loadFolders()

    private func loadFolders() -> [StickerFolder] {
        let fm = FileManager.default
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("Stickers"),
              let names = try? fm.contentsOfDirectory(atPath: root.path) else {
            return []
        }
        var result: [StickerFolder] = []
        for dir in names.sorted() {
            var isDir: ObjCBool = false
            let path = root.appendingPathComponent(dir).path
            guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
            let files = (try? fm.contentsOfDirectory(atPath: path)) ?? []
            let stems = files
                .filter { $0.hasSuffix(".png") || $0.hasSuffix(".jpg") }
                .map { ($0 as NSString).deletingPathExtension }
                .sorted()
            if stems.isEmpty { continue }
            result.append(StickerFolder(name: Y2KString(dir), directory: dir, stickers: stems))
        }
        return result
    }

    func image(folder: StickerFolder, name: String) -> UIImage? {
        let path = "Stickers/\(folder.directory)/\(name).png"
        if let img = UIImage(named: path) { return img }
        guard let url = Bundle.main.url(forResource: "Stickers/\(folder.directory)/\(name)",
                                        withExtension: "png") else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    // MARK: - Saved (user-added) stickers

    private var savedDirectory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("stickers", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Mirrors SavedStickerManager's "sticker_%03d.png" naming.
    func saveUserSticker(_ image: UIImage) -> Bool {
        let defaults = UserDefaults.standard
        let counter = defaults.integer(forKey: "y2k_saved_sticker_counter") + 1
        defaults.set(counter, forKey: "y2k_saved_sticker_counter")
        let name = String(format: "sticker_%03d.png", counter)
        guard let data = image.pngData() else {
            print("Failed to encode sticker.")
            return false
        }
        let url = savedDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url)
            return true
        } catch {
            print("Failed to save sticker: \(error)")
            return false
        }
    }

    func userStickers() -> [UIImage] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: savedDirectory.path) else { return [] }
        return files.filter { $0.hasSuffix(".png") }.sorted().compactMap {
            UIImage(contentsOfFile: savedDirectory.appendingPathComponent($0).path)
        }
    }
}
