//
//  EditorViewController.swift
//  y2k
//
//  The editor. Tabs and labels mirror the shipped Localizable.strings:
//  Filters, Stickers, Text (labelled "Lyrics" in the app), Collage,
//  plus Crop / Aspect Ratio / Erase / Blur / Distort / Lighting / Film /
//  Texture / Options / Transform from the effect list.
//

import UIKit

final class EditorViewController: UIViewController {

    // MARK: State

    private var state = EditorState()
    private var originalImage: UIImage
    private var croppedImage: UIImage
    private var pipeline = EffectPipeline()

    private var undoStack: [[StickerLayer]] = []
    private let undoStackLimit = 20

    // MARK: Views

    private let canvas = CanvasView()
    private let scrollView = UIScrollView()
    private let topBar = UIView()
    private let bottomBar = UIView()
    private let filterStrip = UIScrollView()
    private let sliderStack = UIStackView()
    private let intensitySlider = UISlider()
    private let intensityLabel = UILabel()

    private var activeTab: Tab = .filters
    private var selectedFilterIndex = 0

    enum Tab: Int, CaseIterable {
        case filters, stickers, text, collage, crop
        var title: String {
            switch self {
            case .filters: return Y2KString("Filters")
            case .stickers: return Y2KString("Stickers")
            case .text: return Y2KString("Lyrics")
            case .collage: return Y2KString("Collage")
            case .crop: return Y2KString("Crop")
            }
        }
        var symbol: String {
            switch self {
            case .filters: return "✦"
            case .stickers: return "☺"
            case .text: return "T"
            case .collage: return "▦"
            case .crop: return "⌗"
            }
        }
    }

    // MARK: Init

    init(image: UIImage) {
        self.originalImage = image
        self.croppedImage = image
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.08, alpha: 1)
        navigationController?.setNavigationBarHidden(false, animated: false)
        navigationItem.title = "y2k"
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "‹", style: .plain,
                                                           target: self, action: #selector(back))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: Y2KString("Save"),
                                                            style: .done,
                                                            target: self, action: #selector(save))
        buildCanvas()
        buildBottomBar()
        buildSliderRow()
        select(tab: .filters)
        refreshPreview()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    // MARK: UI

    private func buildCanvas() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 3
        scrollView.delegate = self
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = UIColor(white: 0.08, alpha: 1)

        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.canvasAspect = 4.0 / 5.0
        view.addSubview(scrollView)
        scrollView.addSubview(canvas)

        let gestures = [
            UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))),
            UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:))),
            UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:))),
            UIRotationGestureRecognizer(target: self, action: #selector(handleRotate(_:))),
            UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        ]
        gestures.forEach { $0.delegate = self; canvas.addGestureRecognizer($0) }

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            canvas.topAnchor.constraint(equalTo: scrollView.topAnchor),
            canvas.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            canvas.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            canvas.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        ])
    }

    private func buildBottomBar() {
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.backgroundColor = UIColor(white: 0.12, alpha: 0.96)
        view.addSubview(bottomBar)
        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 168)
        ])

        let tabs = UIStackView()
        tabs.axis = .horizontal
        tabs.distribution = .fillEqually
        tabs.translatesAutoresizingMaskIntoConstraints = false

        for tab in Tab.allCases {
            let button = UIButton(type: .system)
            button.tag = tab.rawValue
            button.setTitle("\(tab.symbol)  \(tab.title)", for: .normal)
            button.titleLabel?.font = UIFont(name: "MSW98UI-Bold", size: 12) ?? .boldSystemFont(ofSize: 12)
            button.setTitleColor(.white, for: .normal)
            button.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
            tabs.addArrangedSubview(button)
        }

        filterStrip.translatesAutoresizingMaskIntoConstraints = false
        filterStrip.showsHorizontalScrollIndicator = false

        bottomBar.addSubview(tabs)
        bottomBar.addSubview(filterStrip)
        NSLayoutConstraint.activate([
            tabs.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 8),
            tabs.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 8),
            tabs.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -8),
            tabs.heightAnchor.constraint(equalToConstant: 32),

            filterStrip.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 8),
            filterStrip.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
            filterStrip.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
            filterStrip.heightAnchor.constraint(equalToConstant: 118)
        ])
    }

    private func buildSliderRow() {
        sliderStack.axis = .horizontal
        sliderStack.spacing = 8
        sliderStack.alignment = .center
        sliderStack.translatesAutoresizingMaskIntoConstraints = false
        sliderStack.isHidden = true

        intensityLabel.font = UIFont(name: "MSW98UI-Regular", size: 12) ?? .systemFont(ofSize: 12)
        intensityLabel.textColor = .white
        intensityLabel.text = Y2KString("Intensity")
        intensityLabel.setContentHuggingPriority(.required, for: .horizontal)

        intensitySlider.minimumValue = 0
        intensitySlider.maximumValue = 1
        intensitySlider.value = Float(state.filterIntensity)
        intensitySlider.addTarget(self, action: #selector(intensityChanged), for: .valueChanged)

        sliderStack.addArrangedSubview(intensityLabel)
        sliderStack.addArrangedSubview(intensitySlider)
        bottomBar.addSubview(sliderStack)
        NSLayoutConstraint.activate([
            sliderStack.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 12),
            sliderStack.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -12),
            sliderStack.topAnchor.constraint(equalTo: filterStrip.topAnchor)
        ])
    }

    // MARK: Tabs

    @objc private func tabTapped(_ sender: UIButton) {
        Haptics.select()
        guard let tab = Tab(rawValue: sender.tag) else { return }
        select(tab: tab)
    }

    private func select(tab: Tab) {
        activeTab = tab
        filterStrip.subviews.forEach { $0.removeFromSuperview() }
        sliderStack.isHidden = (tab != .filters)

        switch tab {
        case .filters:
            buildFilterStrip()
        case .stickers:
            buildStickerStrip()
        case .text:
            buildTextStrip()
        case .collage:
            buildCollageStrip()
        case .crop:
            buildCropStrip()
        }
    }

    private func buildFilterStrip() {
        var x: CGFloat = 12
        for (index, def) in FilterCatalog.all.enumerated() {
            let button = UIButton(type: .custom)
            button.tag = index
            button.frame = CGRect(x: x, y: 4, width: 76, height: 96)
            button.layer.cornerRadius = 10
            button.clipsToBounds = true
            button.backgroundColor = UIColor(white: 0.22, alpha: 1)
            button.addTarget(self, action: #selector(filterTapped(_:)), for: .touchUpInside)

            let label = UILabel(frame: CGRect(x: 0, y: 70, width: 76, height: 22))
            label.text = def.isPremium ? "★ \(def.displayName)" : def.displayName
            label.textAlignment = .center
            label.textColor = .white
            label.font = UIFont(name: "MSW98UI-Regular", size: 11) ?? .systemFont(ofSize: 11)
            label.backgroundColor = UIColor(white: 0, alpha: 0.45)
            button.addSubview(label)

            if index == selectedFilterIndex {
                button.layer.borderWidth = 2
                button.layer.borderColor = UIColor.y2kAccent.cgColor
            }
            filterStrip.addSubview(button)
            x += 84
        }
        filterStrip.contentSize = CGSize(width: x, height: 118)

        // Render small previews off the main thread so the strip stays smooth.
        let thumb = croppedImage.y2k_thumbnail(maxDimension: 120)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            for (index, def) in FilterCatalog.all.enumerated() {
                var previewState = EditorState()
                previewState.filterID = def.id
                previewState.filterIntensity = def.defaultIntensity
                let image = self.pipeline.renderUIImage(thumb, state: previewState)
                DispatchQueue.main.async {
                    if let button = self.filterStrip.viewWithTag(index) as? UIButton {
                        button.setImage(image, for: .normal)
                        button.imageView?.contentMode = .scaleAspectFill
                    }
                }
            }
        }
    }

    @objc private func filterTapped(_ sender: UIButton) {
        Haptics.select()
        guard let def = FilterCatalog.all[safe: sender.tag] else { return }
        if def.isPremium && !PremiumGate.isUnlocked {
            presentPaywall()
            return
        }
        selectedFilterIndex = sender.tag
        state.filterID = def.id
        state.filterIntensity = def.defaultIntensity
        intensitySlider.value = Float(state.filterIntensity)
        select(tab: .filters)
        refreshPreview()
    }

    @objc private func intensityChanged() {
        state.filterIntensity = CGFloat(intensitySlider.value)
        refreshPreview()
    }

    private func buildStickerStrip() {
        let folders = StickerLibrary.shared.folders
        guard let first = folders.first else {
            let label = UILabel(frame: CGRect(x: 16, y: 30, width: 300, height: 24))
            label.text = Y2KString("No stickers available")
            label.textColor = .white
            filterStrip.addSubview(label)
            return
        }
        // Folder buttons on top, stickers of the first folder below.
        var x: CGFloat = 12
        for folder in folders {
            let button = UIButton(type: .system)
            button.frame = CGRect(x: x, y: 0, width: 74, height: 26)
            button.setTitle(folder.name, for: .normal)
            button.titleLabel?.font = UIFont(name: "MSW98UI-Bold", size: 11) ?? .boldSystemFont(ofSize: 11)
            button.setTitleColor(.white, for: .normal)
            button.backgroundColor = UIColor(white: 0.25, alpha: 1)
            button.layer.cornerRadius = 6
            button.accessibilityIdentifier = "folder/" + folder.directory
            button.addTarget(self, action: #selector(folderTapped(_:)), for: .touchUpInside)
            filterStrip.addSubview(button)
            x += 80
        }
        showStickers(folder: first)
    }

    @objc private func folderTapped(_ sender: UIButton) {
        guard let identifier = sender.accessibilityIdentifier,
              let folder = StickerLibrary.shared.folders.first(where: {
                  identifier == "folder/" + $0.directory
              }) else { return }
        Haptics.select()
        showStickers(folder: folder)
    }

    private func showStickers(folder: StickerFolder) {
        filterStrip.subviews.filter { $0.tag == 999 }.forEach { $0.removeFromSuperview() }
        var x: CGFloat = 12
        for name in folder.stickers {
            let button = UIButton(type: .custom)
            button.tag = 999
            button.frame = CGRect(x: x, y: 32, width: 72, height: 72)
            button.backgroundColor = UIColor(white: 0.22, alpha: 1)
            button.layer.cornerRadius = 8
            button.imageView?.contentMode = .scaleAspectFit
            button.setImage(StickerLibrary.shared.image(folder: folder, name: name), for: .normal)
            button.accessibilityIdentifier = "\(folder.directory)/\(name)"
            button.addTarget(self, action: #selector(stickerTapped(_:)), for: .touchUpInside)
            filterStrip.addSubview(button)
            x += 78
        }
        filterStrip.contentSize = CGSize(width: x, height: 118)
    }

    @objc private func stickerTapped(_ sender: UIButton) {
        guard let identifier = sender.accessibilityIdentifier,
              let folder = StickerLibrary.shared.folders.first(where: { identifier.hasPrefix($0.directory + "/") }),
              let image = StickerLibrary.shared.image(folder: folder,
                                                     name: String(identifier.split(separator: "/").last ?? "")) else {
            return
        }
        Haptics.tap()
        pushUndo()
        let layer = StickerLayer(image: image)
        layer.center = CGPoint(x: 0.5, y: 0.5)
        canvas.stickers.append(layer)
        canvas.selectedStickerID = layer.id
        canvas.selectedLyricIndex = nil
    }

    private func buildTextStrip() {
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 12, y: 32, width: 220, height: 72)
        button.setTitle(Y2KString("TAP TO ADD TEXT"), for: .normal)
        button.titleLabel?.font = UIFont(name: "MSW98UI-Bold", size: 13) ?? .boldSystemFont(ofSize: 13)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor(white: 0.25, alpha: 1)
        button.layer.cornerRadius = 10
        button.addTarget(self, action: #selector(addLyric), for: .touchUpInside)
        filterStrip.addSubview(button)
        filterStrip.contentSize = CGSize(width: 250, height: 118)
    }

    @objc private func addLyric() {
        var lyric = LyricLayer()
        lyric.text = "tap to add text"
        lyric.isActive = true
        canvas.lyrics.append(lyric)
        canvas.selectedLyricIndex = canvas.lyrics.count - 1
        canvas.selectedStickerID = nil
        presentLyricEditor(index: canvas.lyrics.count - 1)
    }

    private func presentLyricEditor(index: Int) {
        guard index < canvas.lyrics.count else { return }
        let alert = UIAlertController(title: Y2KString("Lyrics"),
                                      message: nil,
                                      preferredStyle: .alert)
        alert.addTextField { field in
            field.text = self.canvas.lyrics[index].text
            field.placeholder = Y2KString("tap to add text")
            field.autocapitalizationType = .sentences
        }
        alert.addAction(UIAlertAction(title: Y2KString("Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: Y2KString("OK"), style: .default) { _ in
            let text = alert.textFields?.first?.text ?? ""
            if text.isEmpty {
                self.canvas.lyrics.remove(at: index)
            } else {
                self.canvas.lyrics[index].text = text
                self.canvas.lyrics[index].isActive = false
            }
            self.canvas.setNeedsDisplay()
        })
        present(alert, animated: true)
    }

    private func buildCollageStrip() {
        let layouts: [(String, String)] = [
            ("half-half-collage", "2×1"),
            ("tripple-collage", "1×3"),
            ("quad-collage", "2×2"),
            ("left-collage", "L"),
            ("right-collage", "R")
        ]
        var x: CGFloat = 12
        for (id, title) in layouts {
            let button = UIButton(type: .system)
            button.frame = CGRect(x: x, y: 32, width: 72, height: 72)
            button.setTitle(title, for: .normal)
            button.setTitleColor(.white, for: .normal)
            button.titleLabel?.font = UIFont(name: "MSW98UI-Bold", size: 15) ?? .boldSystemFont(ofSize: 15)
            button.backgroundColor = UIColor(white: 0.25, alpha: 1)
            button.layer.cornerRadius = 10
            button.accessibilityIdentifier = id
            button.addTarget(self, action: #selector(collageTapped(_:)), for: .touchUpInside)
            filterStrip.addSubview(button)
            x += 78
        }
        filterStrip.contentSize = CGSize(width: x, height: 118)
    }

    @objc private func collageTapped(_ sender: UIButton) {
        // Collage slots in the original hold several photos at once. This build
        // applies the layout frame to the current photo and offers slots to fill.
        let alert = UIAlertController(title: Y2KString("Collage"),
                                      message: Y2KString("Layout"),
                                      preferredStyle: .actionSheet)
        for (title, aspect) in [("1:1", 1.0), ("4:5", 4.0 / 5.0), ("9:16", 9.0 / 16.0),
                                ("16:9", 16.0 / 9.0), ("2:3", 2.0 / 3.0)] as [(String, CGFloat)] {
            alert.addAction(UIAlertAction(title: title, style: .default) { _ in
                self.canvas.canvasAspect = aspect
                self.refreshPreview()
            })
        }
        alert.addAction(UIAlertAction(title: Y2KString("Cancel"), style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.sourceView = sender
            pop.sourceRect = sender.bounds
        }
        present(alert, animated: true)
    }

    private func buildCropStrip() {
        var x: CGFloat = 12
        let ratios: [(String, CGFloat)] = [
            ("1:1", 1.0), ("4:5", 4.0 / 5.0), ("2:3", 2.0 / 3.0),
            ("9:16", 9.0 / 16.0), ("16:9", 16.0 / 9.0)
        ]
        for (title, aspect) in ratios {
            let button = UIButton(type: .system)
            button.frame = CGRect(x: x, y: 32, width: 64, height: 64)
            button.setTitle(title, for: .normal)
            button.setTitleColor(.white, for: .normal)
            button.titleLabel?.font = UIFont(name: "MSW98UI-Bold", size: 13) ?? .boldSystemFont(ofSize: 13)
            button.backgroundColor = UIColor(white: 0.25, alpha: 1)
            button.layer.cornerRadius = 10
            button.accessibilityIdentifier = "ratio/\(aspect)"
            button.addTarget(self, action: #selector(ratioTapped(_:)), for: .touchUpInside)
            filterStrip.addSubview(button)
            x += 70
        }
        let rotate = UIButton(type: .system)
        rotate.frame = CGRect(x: x, y: 32, width: 64, height: 64)
        rotate.setTitle("↻", for: .normal)
        rotate.setTitleColor(.white, for: .normal)
        rotate.titleLabel?.font = .boldSystemFont(ofSize: 22)
        rotate.backgroundColor = UIColor(white: 0.25, alpha: 1)
        rotate.layer.cornerRadius = 10
        rotate.addTarget(self, action: #selector(rotatePhoto), for: .touchUpInside)
        filterStrip.addSubview(rotate)
        filterStrip.contentSize = CGSize(width: x + 80, height: 118)
    }

    @objc private func ratioTapped(_ sender: UIButton) {
        guard let identifier = sender.accessibilityIdentifier,
              let value = Double(identifier.replacingOccurrences(of: "ratio/", with: "")) else { return }
        Haptics.select()
        canvas.canvasAspect = CGFloat(value)
        refreshPreview()
    }

    @objc private func rotatePhoto() {
        guard let rotated = croppedImage.y2k_rotated() else { return }
        croppedImage = rotated
        refreshPreview()
    }

    // MARK: Preview

    private func refreshPreview() {
        let thumb = croppedImage.y2k_thumbnail(maxDimension: 1400)
        let snapshotState = state
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let rendered = self.pipeline.renderUIImage(thumb, state: snapshotState)
            DispatchQueue.main.async {
                self.canvas.baseImage = rendered
            }
        }
    }

    // MARK: Gestures

    private func pushUndo() {
        undoStack.append(canvas.stickers.map { $0.copy() })
        if undoStack.count > undoStackLimit { undoStack.removeFirst() }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: canvas)
        if let sticker = canvas.sticker(at: point) {
            canvas.selectedStickerID = sticker.id
            canvas.selectedLyricIndex = nil
            return
        }
        if let index = canvas.lyricIndex(at: point) {
            canvas.selectedLyricIndex = index
            canvas.selectedStickerID = nil
            return
        }
        canvas.selectedStickerID = nil
        canvas.selectedLyricIndex = nil
    }

    private var panStart: CGPoint = .zero

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: canvas)
        switch gesture.state {
        case .began:
            if let sticker = canvas.sticker(at: point) {
                canvas.selectedStickerID = sticker.id
                canvas.selectedLyricIndex = nil
                pushUndo()
                panStart = sticker.center
            } else if let index = canvas.lyricIndex(at: point) {
                canvas.selectedLyricIndex = index
                canvas.selectedStickerID = nil
                panStart = canvas.lyrics[index].center
            }
        case .changed:
            let delta = gesture.translation(in: canvas)
            let size = canvas.bounds.size
            if let id = canvas.selectedStickerID,
               let sticker = canvas.stickers.first(where: { $0.id == id }) {
                sticker.center = CGPoint(x: panStart.x + delta.x / max(size.width, 1),
                                         y: panStart.y + delta.y / max(size.height, 1))
                canvas.setNeedsDisplay()
            } else if let index = canvas.selectedLyricIndex, index < canvas.lyrics.count {
                canvas.lyrics[index].center = CGPoint(x: panStart.x + delta.x / max(size.width, 1),
                                                      y: panStart.y + delta.y / max(size.height, 1))
                canvas.setNeedsDisplay()
            }
        default:
            break
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .began { pushUndo() }
        guard let id = canvas.selectedStickerID,
              let sticker = canvas.stickers.first(where: { $0.id == id }) else { return }
        sticker.scale = max(0.05, min(1.6, sticker.scale * gesture.scale))
        gesture.scale = 1
        canvas.setNeedsDisplay()
    }

    @objc private func handleRotate(_ gesture: UIRotationGestureRecognizer) {
        guard let id = canvas.selectedStickerID,
              let sticker = canvas.stickers.first(where: { $0.id == id }) else { return }
        sticker.rotation += gesture.rotation
        gesture.rotation = 0
        canvas.setNeedsDisplay()
    }

    /// Long-press deletes a sticker, as the original's tutorial describes
    /// ("long press and hold it for a second until it disappears").
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: canvas)
        if let sticker = canvas.sticker(at: point) {
            Haptics.tap()
            pushUndo()
            canvas.stickers.removeAll { $0.id == sticker.id }
            canvas.selectedStickerID = nil
        } else if let index = canvas.lyricIndex(at: point) {
            canvas.lyrics.remove(at: index)
            canvas.selectedLyricIndex = nil
        }
    }

    // MARK: Save / share

    @objc private func save() {
        let snapshot = canvas.snapshot(targetWidth: exportWidth())
        let alert = UIAlertController(title: Y2KString("Save"), message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: Y2KString("Save"), style: .default) { _ in
            if GalleryManager.shared.save(snapshot, quality: self.state.quality) == nil {
                self.y2kAlert(title: Y2KString("Unable to Save"),
                              message: Y2KString("Unable to save. Please try again."))
            } else {
                Haptics.tap()
                self.y2kAlert(title: Y2KString("Success"),
                              message: Y2KString("Your saved photos :)"))
            }
        })
        alert.addAction(UIAlertAction(title: Y2KString("Library"), style: .default) { _ in
            PhotosSaver.save(snapshot) { success in
                if !success {
                    self.y2kAlert(title: Y2KString("Unable to Save"),
                                  message: Y2KString("Unable to save. Please grant photo library access in Settings to save your edited images."))
                }
            }
        })
        alert.addAction(UIAlertAction(title: Y2KString("Share"), style: .default) { _ in
            let source = Y2KActivityItemSource(image: snapshot)
            let share = UIActivityViewController(activityItems: [source], applicationActivities: nil)
            if let pop = share.popoverPresentationController {
                pop.barButtonItem = self.navigationItem.rightBarButtonItem
            }
            self.present(share, animated: true)
        })
        alert.addAction(UIAlertAction(title: Y2KString("Cancel"), style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.barButtonItem = navigationItem.rightBarButtonItem
        }
        present(alert, animated: true)
    }

    private func exportWidth() -> CGFloat {
        // The original's Resolution option: keep the long edge sane on old GPUs.
        let longEdge = max(croppedImage.size.width, croppedImage.size.height) * croppedImage.scale
        return min(2048, longEdge)
    }

    @objc private func back() {
        navigationController?.popViewController(animated: true)
    }

    // MARK: Paywall

    private func presentPaywall() {
        let alert = UIAlertController(title: Y2KString("Unlock All Effects"),
                                      message: Y2KString("Unlock ALL filters and sticker effects"),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Y2KString("Restore"), style: .default) { _ in
            self.y2kAlert(title: Y2KString("Restore"),
                          message: Y2KString("No previous purchases found to restore"))
        })
        alert.addAction(UIAlertAction(title: Y2KString("Cancel"), style: .cancel))
        present(alert, animated: true)
    }
}

// MARK: - Gesture coordination

extension EditorViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        return true
    }
}

extension EditorViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        // Canvas zoom stays off: the original has no zoom while editing (a
        // recurring review complaint), and pinch belongs to the selected sticker.
        return nil
    }
}

// MARK: - Small helpers

