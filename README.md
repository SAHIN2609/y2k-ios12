# y2k — iOS 12 clone of y2k 2.03

A working reconstruction of **y2k: 2000s photo editor** (com.abel.y2k, version
2.03, by Abel Thomas Noble / Brick and Yarn LLC) rebuilt to run on **iOS 12**,
packaged so you can install it on a jailbroken iPhone with FileZilla + SSH.

The app source is in `Y2K/`, the original assets it uses (28 `.cube` LUTs, the 8
bundled fonts, 11 localisations, the real app icon) are in `Resources/`.

---

## 1. What the shipped IPA actually is — read this first

I analysed `y2k_2.03_631ylo8y.ipa` before writing anything. These are facts from
the file, not guesses:

| Finding | Evidence |
|---|---|
| Real App Store app, version 2.03, bundle `com.abel.y2k` | `Info.plist` |
| **Built with Xcode 26.0.1 / iOS 26 SDK**, `MinimumOSVersion = 17.0` | `Info.plist`, `LC_BUILD_VERSION minos 17.0.0 sdk 26.0.0` |
| **Swift 5 + SwiftUI**, not Objective-C | `_TtC3y2k…` Swift classes, `$s7SwiftUI…` symbols |
| Uses **iOS 16/17-era SwiftUI** (`NavigationStack`, `PresentationDetent`, `Layout` protocol, `FocusState`, `@Observable`) | Swift type references in the binary |
| **Metal / GPUImage3 shaders** for every effect | `default.metallib`, `GPUImage/MetalRendering.swift`, ~90 GPUImage operations |
| **Not encrypted** (`cryptid = 0`) but **stripped** — no symbol table, no Swift interface, no source | `LC_ENCRYPTION_INFO_64`, code signature |
| Ships **junk injection dylibs** from a pirate-decrypt service: `Fixipa1.dylib` (declares `PicsArt.dylib`), `Fixipa2.dylib` (declares `KineMasterCheat.dylib`), `3BodSyPlus.dylib` (`3BodSyPatch.dylib`), `CydiaSubstrate`, `libsubstrate` | each dylib's `LC_ID_DYLIB` name, `DecryptedBy = @FastDecryptBot` |
| Firebase/Google frameworks are **0-byte stubs** (16 KB empty Mach-O) | `Frameworks/*.framework/*` |

### Why "clone the IPA and make it work on iOS 12" is not possible

The binary was compiled against the iOS 26 SDK with `minos 17.0`. Every SwiftUI
view in it is a call into a SwiftUI runtime that **iOS 12 does not have** — on
iOS 12 `dyld` fails at load time on `_$s7SwiftUI15NavigationStackVMn` and the
process dies before `main`. Changing `MinimumOSVersion` in `Info.plist` changes
nothing: the version floor is baked into `LC_BUILD_VERSION`, and the *actual*
requirement is the SwiftUI/iOS 17 API surface, not the plist string.

Downgrading that binary would mean writing iOS 12 replacements for iOS 16/17
SwiftUI internals and Metal shaders the app calls — i.e. reimplementing the app.
So this project **is** that reimplementation: the same product, the same assets,
the same strings, built with UIKit + Core Image against the iOS 12 SDK.

### Two things this clone cannot carry over

* **Sticker CDN.** The original pulls its sticker library from Firebase Storage
  (`y2k-app.firebasestorage.app`) with fallback bookkeeping
  (`sticker_cdn_use_fallback`, "Showing cached stickers"). That bucket is not
  reachable from a clone, so `Resources/Stickers/` holds a **placeholder pack**
  I generated (30 shapes in the original's folder taxonomy: Black, White, Pink,
  Red, Coins, Stars, Hearts, Flowers, Text, Frames). Drop your own PNGs into
  those folders — the app reads whatever is there.
* **y2k plus / StoreKit.** In-app purchases need a signed receipt; a sideloaded
  clone has none. The premium gate is a local flag that defaults to **unlocked**,
  so every filter is usable. See `PremiumGate` in
  `Y2K/Views/SupportingViews.swift`.

---

## 2. What is in the clone

**Filters — the real LUTs.** All 28 `.cube` files from the app ship in
`Resources/LUTs/` and are parsed at runtime (`FilterCatalog.swift`), with the
intensity slider blending the grade over the original (`CIDissolveTransition`).
Filter order follows the effect list in the binary.

**Effects** (`EffectPipeline.swift`), each an iOS 12-safe Core Image chain:

| Effect | Implementation |
|---|---|
| Light leak | `CIRadialGradient` + `CISoftLightBlendMode` (matches the app's `Failed to load light-leak asset` path) |
| Highlight/shadow wash | `CIHighlightShadowAdjust` (the app links this exact filter) |
| Blur / Motion Blur / Zoom Blur | `CIGaussianBlur`, `CIMotionBlur`, `CIZoomBlur` |
| Pixelation | downscale + `CIPixellate` + upscale |
| Ghost distort | RGB channel offsets recombined |
| Glow | `CIBloom` + `CIScreenBlendMode` |
| Tint | `CIConstantColorGenerator` + `CIMultiplyBlendMode` |
| Grain | `CIRandomGenerator` + soft light (the app's `NoisyFilter`/`GrainyFilter`) |
| Vignette, Sketch, Invert, Exposure, Contrast | `CIVignetteEffect`, `CIEdgeWork`, `CIColorInvert`, `CIExposureAdjust`, `CIColorControls` |

**Editor UI** — filter carousel with live previews, stickers with drag / pinch /
rotate / long-press-delete, 9 blend modes, lyrics text with the original's 8
fonts (stroke + rotation), aspect ratios 1:1, 4:5, 2:3, 9:16, 16:9, crop/rotate,
undo stack (limit 20), save to the in-app gallery, save to Photos, and share
with the original's caption `⋆˚✿˚° made with y2k °˚✿˚⋆`.

**Localisation** — the shipped `Localizable.strings` for ar, de, es, fr, hi, it,
pt-BR, ru, uk, zh-Hant plus a completed `en` table, switchable in Settings.

---

## 3. The .deb that is already here

`y2k_2.03_ios12_iphoneos-arm.deb` (6.4 MB) is packaged and structurally verified:
`debian-binary` + `control.tar.gz` + `data.tar.gz`, 112 entries —
`Applications/y2k.app/` with the 28 LUTs, 30 stickers, 11 `.lproj`, 8 fonts and
the icon set, plus `DEBIAN/control` (`Architecture: iphoneos-arm`,
`Depends: firmware (>= 12.0)`).

**It does not contain a compiled `y2k` binary.** This machine is Windows with no
iOS SDK, so nothing was compiled; the package is the resource/asset payload with
the correct on-device layout. Add the executable before installing:

```bash
# on a Mac, after `make package` or an Xcode archive
ldid -SY2K/Support/y2k.entitlements y2k.app/y2k
mkdir -p debroot/Applications debroot/DEBIAN
cp -R y2k.app debroot/Applications/
cp control debroot/DEBIAN/ && printf '2.0\n' > debroot/debian-binary
(cd debroot && tar -czf ../control.tar.gz ./DEBIAN && tar -czf ../data.tar.gz ./Applications)
# then ar r the three members in order: debian-binary, control.tar.gz, data.tar.gz
```

## 4. Build it

### Option A — Theos (what produces the .deb directly)

```bash
export THEOS=~/theos
cd y2k-ios12
make package FINALPACKAGE=1
# → packages/com.y2k.ios12_2.03_iphoneos-arm.deb
```

`Makefile` builds `y2k.app` from `Y2K/*.swift`, stages `Resources/` (LUTs,
stickers, fonts, .lproj, icons) into the bundle and signs the binary with `ldid`
using `Y2K/Support/y2k.entitlements`.

### Option B — Xcode + XcodeGen

```bash
brew install xcodegen
cd y2k-ios12
xcodegen generate
open y2k.xcodeproj
# Product ▸ Archive, or Product ▸ Build with "Any iOS Device"
```

`project.yml` sets `IPHONEOS_DEPLOYMENT_TARGET = 12.0` and disables signing so
the product can be ldid-signed afterwards. Then:

```bash
ldid -SY2K/Support/y2k.entitlements y2k.app/y2k
./package-deb.sh y2k.app
```

`package-deb.sh` builds the Debian archive layout
(`Applications/y2k.app/…` + `DEBIAN/control`).

---

## 5. Install with FileZilla (jailbroken iOS 12 device)

You need a jailbroken device (unc0ver / checkra1n / Dopamine on iOS 12–15,
palera1n on 15+) with **OpenSSH** installed — rootless jailbreaks store apps in
`/var/jb/Applications` instead of `/Applications`; use a rootful jailbreak for
this package.

1. **FileZilla ▸ File ▸ Site Manager ▸ New site**
   * Protocol: **SFTP - SSH File Transfer Protocol**
   * Host: your iPhone's IP (Settings ▸ Wi-Fi ▸ ⓘ)
   * Port: **22**
   * Logon type: Normal, user **root**, password **alpine** (or your changed
     root password)
   * Click **Connect**, accept the host key.
2. Drag `com.y2k.ios12_2.03_iphoneos-arm.deb` into **`/var/mobile/Documents/`**
   (any writable folder works; don't drop it in `/`).
3. Open a terminal — Terminal, PuTTY, or FileZilla's *Edit ▸ Directory
   listing filters* is not a shell, so use SSH:

   ```bash
   ssh root@<iphone-ip>
   cd /var/mobile/Documents
   dpkg -i com.y2k.ios12_2.03_iphoneos-arm.deb
   uicache -a          # refresh the icon cache
   killall -9 SpringBoard 2>/dev/null || true
   ```

4. The **y2k** icon appears on the home screen. On iOS 12 the app runs from
   `/Applications/y2k.app` and does not need Substrate.

**Alternative without SSH:** Filza File Manager on the device can install a
`.deb` by tapping it (choose *Installer*), which is handy if you prefer to only
use FileZilla to copy the file across.

### If the app installs but will not launch

* `dpkg -i` refused with "architecture" — your package is arm64-only; build with
  `ARCHS=arm64` for an A7–A11 device or `arm64e` for A12+.
* It bounces and closes: the binary is unsigned or the entitlements are wrong —
  re-run `ldid -SY2K/Support/y2k.entitlements y2k.app/y2k` **before**
  packaging.
* No icon after install: `uicache -a` again, or respring.
* A filter shows "Failed to load LUT filter" in the console: the `.cube` files
  did not get staged into the bundle — check
  `/Applications/y2k.app/LUTs/` on the device.

---

## 6. Building it without a Mac — what does not work

Recorded here so it is not tried twice:

* **GitHub macOS runners** were refused on this account (job cancelled within
  seconds, before any step ran). Free personal accounts do not get macOS
  minutes without a payment method on file.
* **GitHub Linux runners** start fine, and the project builds a valid `.deb`
  there — but the executable cannot be produced. A Linux `swiftc` ships no
  `arm64-apple-ios` standard-library modules, so every compile fails with
  `unable to load standard library for target 'arm64-apple-ios12.0'`. Apple
  publishes no Swift SDK for iOS targets from Linux; `swift-sdk-generator`
  supports Linux and FreeBSD targets only.
* **Swift for Windows** installs a compiler, but its WiX bundle failed on the
  Windows box here (`0x80070002` on `bld.asserts.msi`), and even installed it
  would hit the same missing iOS stdlib modules.

The supported paths are a Mac with Xcode (Theos or XcodeGen), or an iOS
cross-toolchain that ships Apple's own iOS Swift modules.

## 7. Honest status

* The source here is **written from the observed behaviour and assets of the
  shipped app**, not recovered from its code — the binary has no symbols and no
  Swift interface to decompile. Layout and wording follow the app's own
  `Localizable.strings` and asset names; the rendering pipeline is a
  Core Image reimplementation, so colours will be close but not bit-identical
  to the GPUImage Metal shaders.
* I could not compile or run this here: this machine is Windows with no iOS
  SDK, no Theos and no device. The project is laid out for Theos and XcodeGen
  and should build on macOS, but treat the first build as the real test.
* The .deb itself is produced by `make package` or `package-deb.sh` on a Mac —
  it cannot be built on Windows, and a prebuilt binary would have to be signed
  with a certificate this project does not have.

## 8. Files

```
y2k-ios12/
├── Y2K/
│   ├── Support/    AppDelegate, Compat, AppLanguage, Info.plist, entitlements, LaunchScreen
│   ├── Core/       FilterCatalog (LUT parsing), EffectPipeline, StickerLibrary, GalleryManager
│   ├── Views/      CanvasView (stickers/lyrics/blend modes), SupportingViews (gallery, settings)
│   └── Controllers/ HomeViewController, EditorViewController
├── Resources/
│   ├── LUTs/       28 .cube files from y2k 2.03
│   ├── Stickers/   10 folders, placeholder pack
│   ├── *.lproj/    11 shipped localisations + en
│   ├── *.ttf/otf   the app's 8 fonts
│   └── AppIcon/    icon set derived from the app's 120×120 icon
├── project.yml     XcodeGen spec (iOS 12.0 target)
├── Makefile        Theos build → .deb
├── control         Debian control file
└── package-deb.sh  assemble the .deb from a built y2k.app
```
