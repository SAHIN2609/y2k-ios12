//
//  Compat.swift
//  y2k
//
//  Small shims so the editor runs on iOS 12 while still compiling with a
//  modern SDK. Everything the original app took from iOS 13+ is reimplemented
//  here with iOS 12 safe API.
//

import UIKit

// MARK: - Colour helpers

extension UIColor {
    /// Convenience hex initialiser (RRGGBB).
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }

    /// The y2k chrome: a warm, slightly dirty cream like a 2003 digicam menu.
    static let y2kCream = UIColor(hex: 0xF2EDE1)
    static let y2kInk = UIColor(hex: 0x1B1A17)
    static let y2kAccent = UIColor(hex: 0x7F7F00)
    static let y2kPink = UIColor(hex: 0xE79BA5)
}

// MARK: - System appearance

enum SystemAppearance {
    /// iOS 12 has no system-wide dark mode, so this is purely informational.
    static var isDark: Bool {
        if #available(iOS 13.0, *) {
            return UITraitCollection.current.userInterfaceStyle == .dark
        }
        return false
    }
}

// MARK: - UIActivityViewController source for the share sheet

/// Mirrors `Y2KActivityItemSource`: shares the rendered PNG with the caption
/// "⋆˚✿˚° made with y2k °˚✿˚⋆" the way the original does.
final class Y2KActivityItemSource: NSObject, UIActivityItemSource {
    private let image: UIImage
    private let fileURL: URL?
    private let caption: String

    init(image: UIImage, fileURL: URL? = nil,
         caption: String = "⋆˚✿˚° made with y2k °˚✿˚⋆") {
        self.image = image
        self.fileURL = fileURL
        self.caption = caption
    }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any {
        return image
    }

    func activityViewController(_ controller: UIActivityViewController,
                                itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return image
    }

    func activityViewController(_ controller: UIActivityViewController,
                                subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return caption
    }
}

// MARK: - Haptics (iOS 10+ API, safe everywhere)

enum Haptics {
    static func tap() {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.impactOccurred()
    }
    static func select() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

// MARK: - Alerts

extension UIViewController {
    func y2kAlert(title: String, message: String? = nil,
                  actions: [UIAlertAction] = []) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        if actions.isEmpty {
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel))
        } else {
            actions.forEach(alert.addAction)
        }
        present(alert, animated: true)
    }
}

// MARK: - Indexed access safety

extension Array {
    subscript(safe index: Int) -> Element? {
        return index >= 0 && index < count ? self[index] : nil
    }
}
