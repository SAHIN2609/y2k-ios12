//
//  CanvasView.swift
//  y2k
//
//  The editing canvas: the cropped photo, then stickers and lyrics laid on top,
//  all drawn in a fixed 0…1 coordinate space so the same layout exports at any
//  resolution. Mirrors `StickerCanvas` / `stickersContainer` in the original.
//

import UIKit

// MARK: - Model

enum BlendMode: Int, CaseIterable {
    case normal, multiply, screen, overlay, softLight, hardLight,
         colorBurn, difference, luminosity

    var title: String {
        switch self {
        case .normal: return Y2KString("Normal")
        case .multiply: return Y2KString("Multiply")
        case .screen: return Y2KString("Screen")
        case .overlay: return Y2KString("Overlay")
        case .softLight: return Y2KString("Soft Light")
        case .hardLight: return Y2KString("Hard Light")
        case .colorBurn: return Y2KString("Color Burn")
        case .difference: return Y2KString("Difference")
        case .luminosity: return Y2KString("Luminosity")
        }
    }

    /// CGBlendMode is available on iOS 12 for all of these.
    var cgBlendMode: CGBlendMode {
        switch self {
        case .normal: return .normal
        case .multiply: return .multiply
        case .screen: return .screen
        case .overlay: return .overlay
        case .softLight: return .softLight
        case .hardLight: return .hardLight
        case .colorBurn: return .colorBurn
        case .difference: return .difference
        case .luminosity: return .luminosity
        }
    }
}

/// A sticker placed on the canvas. Position/size are normalised (0…1).
final class StickerLayer {
    let id = UUID()
    var image: UIImage
    var center: CGPoint = CGPoint(x: 0.5, y: 0.5)
    var scale: CGFloat = 0.35        // fraction of canvas width
    var rotation: CGFloat = 0        // radians
    var opacity: CGFloat = 1.0
    var blend: BlendMode = .normal
    var isRemovingBackground: Bool = false

    init(image: UIImage) { self.image = image }

    func copy() -> StickerLayer {
        let c = StickerLayer(image: image)
        c.center = center; c.scale = scale; c.rotation = rotation
        c.opacity = opacity; c.blend = blend
        return c
    }
}

/// A line of "lyrics" text. Mirrors `LyricsEffect` / `InteractiveLyricsView`.
struct LyricLayer {
    var text: String = ""
    var center: CGPoint = CGPoint(x: 0.5, y: 0.82)
    var scale: CGFloat = 0.9
    var rotation: CGFloat = 0
    var fontName: String = "MSW98UI-Regular"
    var color: UIColor = .white
    var strokeColor: UIColor = .black
    var strokeWidth: CGFloat = 2.0
    var alignment: NSTextAlignment = .center
    var isActive: Bool = false
}

// MARK: - Canvas

final class CanvasView: UIView {

    /// The graded photo (already filtered).
    var baseImage: UIImage? { didSet { setNeedsDisplay() } }

    var stickers: [StickerLayer] = [] { didSet { setNeedsDisplay() } }
    var lyrics: [LyricLayer] = [] { didSet { setNeedsDisplay() } }

    var selectedStickerID: UUID? { didSet { setNeedsDisplay() } }
    var selectedLyricIndex: Int? { didSet { setNeedsDisplay() } }

    /// Aspect ratio of the working canvas (1.0 = square, 9/16 etc).
    var canvasAspect: CGFloat = 4.0 / 5.0 {
        didSet { invalidateIntrinsicContentSize(); setNeedsDisplay() }
    }

    /// Draws handles for the selected sticker/lyric.
    var showsSelection = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = true
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric,
                      height: bounds.width / max(canvasAspect, 0.01))
    }

    // MARK: Geometry

    private var canvasRect: CGRect {
        let w = bounds.width
        let h = bounds.height
        let target = w / max(canvasAspect, 0.01)
        if target <= h {
            return CGRect(x: 0, y: (h - target) / 2, width: w, height: target)
        }
        let hw = h * canvasAspect
        return CGRect(x: (w - hw) / 2, y: 0, width: hw, height: h)
    }

    private func rect(for layer: StickerLayer) -> CGRect {
        let c = canvasRect
        let size = layer.image.size
        let w = c.width * layer.scale
        let h = w * (size.height / max(size.width, 1))
        return CGRect(x: c.minX + layer.center.x * c.width - w / 2,
                      y: c.minY + layer.center.y * c.height - h / 2,
                      width: w, height: h)
    }

    // MARK: Drawing

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let c = canvasRect

        // Photo
        if let base = baseImage {
            base.draw(in: c)
        } else {
            UIColor(white: 0.12, alpha: 1).setFill()
            ctx.fill(c)
        }

        // Stickers, in order
        for layer in stickers {
            let r = rect(for: layer)
            guard let image = layer.image.cgImage else { continue }
            ctx.saveGState()
            ctx.setAlpha(layer.opacity)
            ctx.setBlendMode(layer.blend.cgBlendMode)
            ctx.translateBy(x: r.midX, y: r.midY)
            ctx.rotate(by: layer.rotation)
            ctx.draw(image, in: CGRect(x: -r.width / 2, y: -r.height / 2,
                                       width: r.width, height: r.height))
            ctx.restoreGState()

            if showsSelection, let selected = selectedStickerID, selected == layer.id {
                drawHandles(around: r, rotation: layer.rotation, in: ctx)
            }
        }

        // Lyrics
        for (index, lyric) in lyrics.enumerated() {
            drawLyric(lyric, in: c, ctx: ctx)
            if showsSelection, selectedLyricIndex == index {
                let frame = lyricRect(lyric, in: c)
                UIColor.white.setStroke()
                ctx.setLineWidth(1)
                ctx.setLineDash(phase: 0, lengths: [4, 3])
                ctx.stroke(frame)
                ctx.setLineDash(phase: 0, lengths: [])
            }
        }
    }

    private func drawHandles(around r: CGRect, rotation: CGFloat, in ctx: CGContext) {
        ctx.saveGState()
        UIColor.white.setStroke()
        ctx.setLineWidth(1.5)
        ctx.setLineDash(phase: 0, lengths: [5, 3])
        ctx.stroke(r.insetBy(dx: -2, dy: -2))
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.setFillColor(UIColor.white.cgColor)
        let s: CGFloat = 10
        for corner in [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                       CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)] {
            ctx.fillEllipse(in: CGRect(x: corner.x - s / 2, y: corner.y - s / 2, width: s, height: s))
        }
        ctx.restoreGState()
    }

    private func font(for lyric: LyricLayer, in canvas: CGRect) -> UIFont {
        let size = max(10, canvas.width * 0.085 * lyric.scale)
        return UIFont(name: lyric.fontName, size: size) ?? UIFont.systemFont(ofSize: size, weight: .bold)
    }

    private func lyricRect(_ lyric: LyricLayer, in canvas: CGRect) -> CGRect {
        let f = font(for: lyric, in: canvas)
        let maxWidth = canvas.width * 0.94
        let bounding = (lyric.text as NSString).boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: f], context: nil)
        let w = min(maxWidth, ceil(bounding.width) + lyric.strokeWidth * 2 + 8)
        let h = ceil(bounding.height) + lyric.strokeWidth * 2 + 6
        let cx = canvas.minX + lyric.center.x * canvas.width
        let cy = canvas.minY + lyric.center.y * canvas.height
        return CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
    }

    private func drawLyric(_ lyric: LyricLayer, in canvas: CGRect, ctx: CGContext) {
        guard !lyric.text.isEmpty else { return }
        let f = font(for: lyric, in: canvas)
        let para = NSMutableParagraphStyle()
        para.alignment = lyric.alignment
        para.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: f,
            .foregroundColor: lyric.color,
            .strokeColor: lyric.strokeColor,
            .strokeWidth: -lyric.strokeWidth,
            .paragraphStyle: para
        ]
        let r = lyricRect(lyric, in: canvas)
        ctx.saveGState()
        ctx.translateBy(x: r.midX, y: r.midY)
        ctx.rotate(by: lyric.rotation)
        let drawRect = CGRect(x: -r.width / 2, y: -r.height / 2, width: r.width, height: r.height)
        (lyric.text as NSString).draw(with: drawRect,
                                      options: [.usesLineFragmentOrigin, .usesFontLeading],
                                      attributes: attributes, context: nil)
        ctx.restoreGState()
    }

    // MARK: Hit testing

    func sticker(at point: CGPoint) -> StickerLayer? {
        for layer in stickers.reversed() {
            let r = rect(for: layer).insetBy(dx: -12, dy: -12)
            if r.contains(point) { return layer }
        }
        return nil
    }

    func lyricIndex(at point: CGPoint) -> Int? {
        let c = canvasRect
        for (i, lyric) in lyrics.enumerated().reversed() {
            if lyricRect(lyric, in: c).insetBy(dx: -10, dy: -10).contains(point) { return i }
        }
        return nil
    }

    func canvasPoint(_ point: CGPoint) -> CGPoint {
        let c = canvasRect
        return CGPoint(x: (point.x - c.minX) / max(c.width, 1),
                       y: (point.y - c.minY) / max(c.height, 1))
    }

    // MARK: Snapshot (for export)

    /// Renders the whole canvas at `targetWidth` pixels wide.
    func snapshot(targetWidth: CGFloat) -> UIImage {
        let size = CGSize(width: targetWidth, height: targetWidth / max(canvasAspect, 0.01))
        let wasSelectedSticker = selectedStickerID
        let wasSelectedLyric = selectedLyricIndex
        let wasShowing = showsSelection
        selectedStickerID = nil
        selectedLyricIndex = nil
        showsSelection = false

        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        guard let ctx = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return baseImage ?? UIImage()
        }
        // Scale the normalised layout to the export size.
        let target = CGRect(origin: .zero, size: size)
        if let base = baseImage {
            base.draw(in: target)
        } else {
            UIColor.black.setFill(); ctx.fill(target)
        }
        for layer in stickers {
            guard let cg = layer.image.cgImage else { continue }
            let w = size.width * layer.scale
            let h = w * (layer.image.size.height / max(layer.image.size.width, 1))
            ctx.saveGState()
            ctx.setAlpha(layer.opacity)
            ctx.setBlendMode(layer.blend.cgBlendMode)
            ctx.translateBy(x: layer.center.x * size.width, y: layer.center.y * size.height)
            ctx.rotate(by: layer.rotation)
            ctx.draw(cg, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
            ctx.restoreGState()
        }
        for lyric in lyrics {
            guard !lyric.text.isEmpty else { continue }
            let f = font(for: lyric, in: target)
            let para = NSMutableParagraphStyle()
            para.alignment = lyric.alignment
            let attributes: [NSAttributedString.Key: Any] = [
                .font: f,
                .foregroundColor: lyric.color,
                .strokeColor: lyric.strokeColor,
                .strokeWidth: -lyric.strokeWidth,
                .paragraphStyle: para
            ]
            let maxWidth = size.width * 0.94
            let bounding = (lyric.text as NSString).boundingRect(
                with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes, context: nil)
            let w = min(maxWidth, ceil(bounding.width) + lyric.strokeWidth * 2 + 8)
            let h = ceil(bounding.height) + lyric.strokeWidth * 2 + 6
            ctx.saveGState()
            ctx.translateBy(x: lyric.center.x * size.width, y: lyric.center.y * size.height)
            ctx.rotate(by: lyric.rotation)
            (lyric.text as NSString).draw(with: CGRect(x: -w / 2, y: -h / 2, width: w, height: h),
                                          options: [.usesLineFragmentOrigin, .usesFontLeading],
                                          attributes: attributes, context: nil)
            ctx.restoreGState()
        }
        let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()

        selectedStickerID = wasSelectedSticker
        selectedLyricIndex = wasSelectedLyric
        showsSelection = wasShowing
        setNeedsDisplay()
        return image
    }
}
