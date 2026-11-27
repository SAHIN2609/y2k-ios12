//
//  EffectPipeline.swift
//  y2k
//
//  Every adjustment the editor offers, as iOS 12 safe Core Image work.
//
//  Evidence for what the shipped app does (2.03 binary strings):
//    "Failed to load LUT filter", "Failed to load light-leak asset",
//    CISoftLightBlendMode / CIMultiplyBlendMode / CIScreenBlendMode,
//    CIHighlightShadowAdjust (inputShadowAmount/inputHighlightAmount),
//    CIRandomGenerator, CIRadialGradient, CIConstantColorGenerator,
//    GrainyFilter / NoisyFilter (inputIntensity), NormalizeFilter,
//    and the effect class list (NoiseEffect, VignetteEffect, TintEffect,
//    BlurEffect, MotionBlurEffect, ZoomBlurEffect, PixelationEffect,
//    GlowEffect, GhostDistortEffect, …).
//
//  What the original renders with GPUImage3's Metal shaders is reproduced here
//  with Core Image equivalents: same look, no Metal shading language, works on
//  every iOS 12 device including the A7/A8 GPUs.
//

import UIKit
import CoreImage

/// All the mutable editor state that affects the rendered image.
struct EditorState {
    var filterID: String = "VHS"
    var filterIntensity: CGFloat = 0.85

    // Film / texture
    var grain: CGFloat = 0.15          // NoiseEffect / GrainyFilter inputIntensity
    var lightLeak: CGFloat = 0.0       // light-leak overlay opacity
    var vignette: CGFloat = 0.20
    var glow: CGFloat = 0.0

    // Blur family (Blur / Motion Blur / Zoom Blur share one slider in the app)
    var blurAmount: CGFloat = 0.0
    var blurMode: BlurMode = .gaussian

    // Distort
    var pixelation: CGFloat = 0.0      // 0…1, maps to pixel scale 1…40
    var ghostDistort: CGFloat = 0.0

    // Colour
    var tintColor: UIColor? = nil
    var tintAmount: CGFloat = 0.0
    var exposure: CGFloat = 0.0        // -1…1
    var contrast: CGFloat = 0.0        // -1…1
    var invert: Bool = false
    var sketch: Bool = false

    // Quality / resolution are export-time only in the original; kept for UI parity.
    var quality: CGFloat = 0.92

    enum BlurMode: Int, CaseIterable {
        case gaussian, motion, zoom
        var title: String {
            switch self {
            case .gaussian: return Y2KString("Blur")
            case .motion: return Y2KString("Motion Blur")
            case .zoom: return Y2KString("Zoom Blur")
            }
        }
    }
}

final class EffectPipeline {

    /// Shared context — the original also keeps one `CoreImageContext` singleton.
    let context: CIContext
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    init() {
        // `cacheIntermediates` only exists from iOS 12, so this stays compatible.
        let options: [CIContextOption: Any] = [
            .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
            .outputColorSpace: CGColorSpaceCreateDeviceRGB()
        ]
        context = CIContext(options: options)
    }

    // MARK: - Render

    func render(image: CIImage, state: EditorState, scale: CGFloat = 1.0) -> CIImage {
        var output = image

        // 1. LUT grade (the filter itself).
        if let lut = LUTCache.shared.lut(named: state.filterID) {
            output = applyLUT(output, lut: lut, intensity: state.filterIntensity)
        }

        // 2. Light leak — soft-light wash from the top-right, like the shipped
        //    light-leak asset being composited with CISoftLightBlendMode.
        if state.lightLeak > 0.001 {
            output = applyLightLeak(output, amount: state.lightLeak)
        }

        // 3. Highlight/shadow lift for the washed-out 2000s look.
        output = applyHighlightShadow(output)

        // 4. Blur family.
        if state.blurAmount > 0.001 {
            output = applyBlur(output, amount: state.blurAmount, mode: state.blurMode)
        }

        // 5. Pixelation (PixelationEffect).
        if state.pixelation > 0.001 {
            output = applyPixelation(output, amount: state.pixelation)
        }

        // 6. Ghost / chromatic distortion (GhostDistortEffect).
        if state.ghostDistort > 0.001 {
            output = applyGhostDistort(output, amount: state.ghostDistort)
        }

        // 7. Glow (GlowEffect).
        if state.glow > 0.001 {
            output = applyGlow(output, amount: state.glow)
        }

        // 8. Tint (TintEffect).
        if let tint = state.tintColor, state.tintAmount > 0.001 {
            output = applyTint(output, color: tint, amount: state.tintAmount)
        }

        // 9. Exposure / contrast.
        if abs(state.exposure) > 0.001 {
            if let f = CIFilter(name: "CIExposureAdjust", parameters: [
                kCIInputImageKey: output,
                "inputEV": Float(state.exposure)
            ]), let adjusted = f.outputImage { output = adjusted }
        }
        if abs(state.contrast) > 0.001 {
            if let f = CIFilter(name: "CIColorControls", parameters: [
                kCIInputImageKey: output,
                kCIInputContrastKey: NSNumber(value: Double(1.0 + state.contrast)),
                kCIInputBrightnessKey: NSNumber(value: 0.0),
                kCIInputSaturationKey: NSNumber(value: 1.0)
            ]), let adjusted = f.outputImage { output = adjusted }
        }

        // 10. Sketch / invert.
        if state.sketch {
            let f = CIFilter(name: "CIEdgeWork", parameters: [
                kCIInputImageKey: output,
                "inputRadius": 3.0
            ])
            output = f?.outputImage ?? output
        }
        if state.invert {
            let f = CIFilter(name: "CIColorInvert", parameters: [kCIInputImageKey: output])
            output = f?.outputImage ?? output
        }

        // 11. Vignette.
        if state.vignette > 0.001 {
            if let f = CIFilter(name: "CIVignetteEffect", parameters: [
                kCIInputImageKey: output,
                kCIInputIntensityKey: Float(state.vignette * 1.4),
                kCIInputRadiusKey: Float(min(output.extent.width, output.extent.height) * 0.6),
                kCIInputCenterKey: CIVector(x: output.extent.midX, y: output.extent.midY)
            ]), let adjusted = f.outputImage { output = adjusted }
        }

        // 12. Grain last so it sits on top of everything (NoiseEffect).
        if state.grain > 0.001 {
            output = applyGrain(output, amount: state.grain)
        }

        return output.cropped(to: image.extent)
    }

    func renderUIImage(_ image: UIImage, state: EditorState) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let ci = CIImage(cgImage: cg, options: [.colorSpace: colorSpace])
        let out = render(image: ci, state: state)
        guard let result = context.createCGImage(out, from: ci.extent, format: .RGBA8,
                                                 colorSpace: colorSpace) else { return nil }
        return UIImage(cgImage: result, scale: image.scale, orientation: image.imageOrientation)
    }

    // MARK: - Individual effects

    private func applyLUT(_ image: CIImage, lut: CubeLUT, intensity: CGFloat) -> CIImage {
        let cubeData = lut.cubeData()
        guard let filter = CIFilter(name: "CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": lut.size,
            "inputCubeData": cubeData,
            kCIInputImageKey: image,
            "inputColorSpace": colorSpace
        ]), let graded = filter.outputImage else {
            return image
        }
        // Blend the graded image over the original by intensity.
        let t = max(0, min(1, intensity))
        return graded.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: image,
            kCIInputTimeKey: Float(t)
        ])
    }

    private func applyLightLeak(_ image: CIImage, amount: CGFloat) -> CIImage {
        let extent = image.extent
        // A warm radial blob in the upper right.
        let generator = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: extent.maxX * 0.85, y: extent.maxY * 0.85),
            "inputRadius0": 0.0,
            "inputRadius1": Float(min(extent.width, extent.height) * 0.9),
            "inputColor0": CIColor(red: 1.0, green: 0.78, blue: 0.55, alpha: 1.0),
            "inputColor1": CIColor(red: 1.0, green: 0.55, blue: 0.35, alpha: 0.0)
        ])
        guard let leak = generator?.outputImage?.cropped(to: extent) else { return image }

        let alpha = leak.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(amount))
        ])
        // Soft light keeps the highlights from clipping.
        return alpha.applyingFilter("CISoftLightBlendMode", parameters: [
            kCIInputBackgroundImageKey: image
        ]).cropped(to: extent)
    }

    private func applyHighlightShadow(_ image: CIImage) -> CIImage {
        let f = CIFilter(name: "CIHighlightShadowAdjust", parameters: [
            kCIInputImageKey: image,
            "inputShadowAmount": 0.35,     // lift the blacks slightly, digicam style
            "inputHighlightAmount": 0.85,  // pull the highlights down = overexposed look
            "inputRadius": 12.0
        ])
        return f?.outputImage ?? image
    }

    private func applyBlur(_ image: CIImage, amount: CGFloat, mode: EditorState.BlurMode) -> CIImage {
        let extent = image.extent
        switch mode {
        case .gaussian:
            let f = CIFilter(name: "CIGaussianBlur", parameters: [
                kCIInputImageKey: image,
                kCIInputRadiusKey: Float(amount * 20)
            ])
            return f?.outputImage?.cropped(to: extent) ?? image
        case .motion:
            let f = CIFilter(name: "CIMotionBlur", parameters: [
                kCIInputImageKey: image,
                "inputRadius": Float(amount * 30),
                "inputAngle": 0.0
            ])
            return f?.outputImage?.cropped(to: extent) ?? image
        case .zoom:
            let f = CIFilter(name: "CIZoomBlur", parameters: [
                kCIInputImageKey: image,
                kCIInputCenterKey: CIVector(x: extent.midX, y: extent.midY),
                kCIInputAmountKey: Float(amount * 40)
            ])
            return f?.outputImage?.cropped(to: extent) ?? image
        }
    }

    private func applyPixelation(_ image: CIImage, amount: CGFloat) -> CIImage {
        let extent = image.extent
        let scale = max(1.0, amount * 40.0)
        let small = image.transformed(by: CGAffineTransform(scaleX: 1.0 / scale, y: 1.0 / scale))
        let f = CIFilter(name: "CIPixellate", parameters: [
            kCIInputImageKey: small,
            kCIInputScaleKey: 1.0
        ])
        guard let pixel = f?.outputImage else { return image }
        let back = pixel.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return back.cropped(to: extent)
    }

    private func applyGhostDistort(_ image: CIImage, amount: CGFloat) -> CIImage {
        let extent = image.extent
        let offset = amount * 12.0
        // Red shifted right, blue shifted left — cheap chromatic ghosting.
        let r = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ]).transformed(by: CGAffineTransform(translationX: offset, y: 0))
        let g = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])
        let b = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0)
        ]).transformed(by: CGAffineTransform(translationX: -offset, y: 0))

        let rg = r.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: g])
        return rg.applyingFilter("CIAdditionCompositing", parameters: [
            kCIInputBackgroundImageKey: b
        ]).cropped(to: extent)
    }

    private func applyGlow(_ image: CIImage, amount: CGFloat) -> CIImage {
        let extent = image.extent
        let bloom = image.applyingFilter("CIBloom", parameters: [
            kCIInputRadiusKey: Float(amount * 24.0),
            kCIInputIntensityKey: Float(amount * 1.6)
        ])
        // Screen blend so the glow only ever brightens.
        return bloom.applyingFilter("CIScreenBlendMode", parameters: [
            kCIInputBackgroundImageKey: image
        ]).cropped(to: extent)
    }

    private func applyTint(_ image: CIImage, color: UIColor, amount: CGFloat) -> CIImage {
        let extent = image.extent
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let constant = CIImage(color: CIColor(red: r, green: g, blue: b))
            .cropped(to: extent)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(amount * 0.55))
            ])
        return constant.applyingFilter("CIMultiplyBlendMode", parameters: [
            kCIInputBackgroundImageKey: image
        ]).cropped(to: extent)
    }

    private func applyGrain(_ image: CIImage, amount: CGFloat) -> CIImage {
        let extent = image.extent
        let noise = CIFilter(name: "CIRandomGenerator")?.outputImage ?? image
        // Monochrome the noise, then overlay it with a low alpha.
        let mono = noise.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0),
            "inputGVector": CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0),
            "inputBVector": CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(amount * 0.35))
        ]).cropped(to: extent)
        return mono.applyingFilter("CISoftLightBlendMode", parameters: [
            kCIInputBackgroundImageKey: image
        ]).cropped(to: extent)
    }
}
