//
//  FilterCatalog.swift
//  y2k
//
//  The filter list and the LUT loader. The .cube files shipped in
//  Resources/LUTs are the ones from the shipped 2.03 app (16 / 25 / 32 / 33
//  sized tables, various vendors), parsed here rather than through
//  CIColorCubeWithColorSpace because that initialiser needs the cube data
//  laid out in premultiplied RGBA float order, which we build once and cache.
//

import UIKit
import CoreImage

struct FilterDefinition {
    let id: String            // LUT basename, also the effect class suffix
    let displayName: String   // shown in the filter carousel
    let isPremium: Bool
    let defaultIntensity: CGFloat
}

enum FilterCatalog {

    /// Order mirrors the effect order found in the 2.03 binary's effect list.
    static let all: [FilterDefinition] = [
        .init(id: "VHS",        displayName: "VHS",         isPremium: false, defaultIntensity: 0.85),
        .init(id: "iPhone3G",   displayName: "iPhone 3G",   isPremium: false, defaultIntensity: 1.0),
        .init(id: "Camcorder",  displayName: "Camcorder",   isPremium: false, defaultIntensity: 0.9),
        .init(id: "Kodak",      displayName: "Kodak",       isPremium: false, defaultIntensity: 0.8),
        .init(id: "FujiFilm",   displayName: "FujiFilm",    isPremium: false, defaultIntensity: 0.8),
        .init(id: "Nashville",  displayName: "Nashville",   isPremium: false, defaultIntensity: 0.8),
        .init(id: "EarlyBird",  displayName: "EarlyBird",   isPremium: false, defaultIntensity: 0.8),
        .init(id: "1977",       displayName: "1977",        isPremium: false, defaultIntensity: 0.8),
        .init(id: "2016",       displayName: "2016",        isPremium: false, defaultIntensity: 0.8),
        .init(id: "Insta",      displayName: "Insta",       isPremium: false, defaultIntensity: 0.8),
        .init(id: "Moody",      displayName: "Moody",       isPremium: false, defaultIntensity: 0.85),
        .init(id: "Dream",      displayName: "Dream",       isPremium: false, defaultIntensity: 0.85),
        .init(id: "Ethereal",   displayName: "Ethereal",    isPremium: true,  defaultIntensity: 0.85),
        .init(id: "Fog",        displayName: "Fog",         isPremium: true,  defaultIntensity: 0.8),
        .init(id: "Ghost",      displayName: "Ghost",       isPremium: true,  defaultIntensity: 0.9),
        .init(id: "Cry",        displayName: "Cry",         isPremium: true,  defaultIntensity: 0.9),
        .init(id: "Furry",      displayName: "Furry",       isPremium: true,  defaultIntensity: 0.9),
        .init(id: "Misa",       displayName: "Misa",        isPremium: true,  defaultIntensity: 0.9),
        .init(id: "Divergent",  displayName: "Divergent",   isPremium: true,  defaultIntensity: 1.0),
        .init(id: "Cyberpunk",  displayName: "Cyberpunk",   isPremium: true,  defaultIntensity: 1.0),
        .init(id: "NightVision",displayName: "Night Vision",isPremium: true,  defaultIntensity: 1.0),
        .init(id: "Numetal",    displayName: "Numetal",     isPremium: true,  defaultIntensity: 0.9),
        .init(id: "Suprised",   displayName: "Surprised",   isPremium: true,  defaultIntensity: 0.9),
        .init(id: "Victorian",  displayName: "Victorian",   isPremium: true,  defaultIntensity: 0.8),
        .init(id: "Squint",     displayName: "Squint",      isPremium: true,  defaultIntensity: 0.85),
        .init(id: "Laugh",      displayName: "Laugh",       isPremium: true,  defaultIntensity: 0.85),
        .init(id: "Cat",        displayName: "Cat",         isPremium: true,  defaultIntensity: 0.9),
        .init(id: "Booth",      displayName: "Booth",       isPremium: true,  defaultIntensity: 0.9)
    ]

    static func definition(for id: String) -> FilterDefinition? {
        return all.first { $0.id == id }
    }
}

// MARK: - CUBE parsing

/// One parsed .cube table. `size` is the LUT_3D_SIZE (16…33).
struct CubeLUT {
    let size: Int
    /// RGB triples in the file's own order (red varies fastest).
    let values: [Float]

    /// Core Image wants premultiplied RGBA floats; we build it lazily and cache.
    func cubeData() -> Data {
        let count = size * size * size
        var rgba = [Float](repeating: 1.0, count: count * 4)
        for i in 0..<count {
            let base = i * 3
            rgba[i * 4 + 0] = values[base + 0]
            rgba[i * 4 + 1] = values[base + 1]
            rgba[i * 4 + 2] = values[base + 2]
            rgba[i * 4 + 3] = 1.0
        }
        return rgba.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func load(named name: String) -> CubeLUT? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "cube"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            print("Failed to load LUT filter \(name)")
            return nil
        }
        var size = 0
        var values: [Float] = []
        text.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { return }
            if trimmed.uppercased().hasPrefix("LUT_3D_SIZE") {
                size = Int(trimmed.split(separator: " ").last ?? "0") ?? 0
                return
            }
            if trimmed.uppercased().hasPrefix("TITLE") ||
                trimmed.uppercased().hasPrefix("DOMAIN_MIN") ||
                trimmed.uppercased().hasPrefix("DOMAIN_MAX") { return }
            let parts = trimmed.split(separator: " ")
            guard parts.count == 3,
                  let r = Float(parts[0]), let g = Float(parts[1]), let b = Float(parts[2]) else { return }
            values.append(r); values.append(g); values.append(b)
        }
        guard size > 0, values.count == size * size * size * 3 else {
            print("Failed to load LUT filter \(name): size \(size), values \(values.count / 3)")
            return nil
        }
        return CubeLUT(size: size, values: values)
    }
}

// MARK: - Cube cache

final class LUTCache {
    static let shared = LUTCache()
    private var cache: [String: CubeLUT] = [:]
    private let queue = DispatchQueue(label: "com.y2k.lutcache")

    func lut(named name: String) -> CubeLUT? {
        if let hit = cache[name] { return hit }
        let parsed = CubeLUT.load(named: name)
        if let parsed = parsed { cache[name] = parsed }
        return parsed
    }
}
