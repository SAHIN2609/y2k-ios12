//
//  HomeViewController.swift
//  y2k
//
//  Home: pick a photo, open the gallery, settings. Copy follows the shipped
//  Localizable.strings ("Tap to Upload Photo", "Your saved photos :)",
//  "Filters", "Stickers", "Lyrics", "Collage", "Settings").
//

import UIKit
import Photos

final class HomeViewController: UIViewController {

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let uploadButton = UIButton(type: .system)
    private let galleryButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)
    private let recentStack = UIStackView()

    private let pipeline = EffectPipeline()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .y2kCream
        navigationController?.setNavigationBarHidden(true, animated: false)
        buildUI()
        reloadRecent()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        reloadRecent()
    }

    private func buildUI() {
        titleLabel.text = "y2k"
        titleLabel.font = UIFont(name: "MSW98UI-Bold", size: 46) ?? .boldSystemFont(ofSize: 46)
        titleLabel.textColor = .y2kInk
        titleLabel.textAlignment = .center

        subtitleLabel.text = Y2KString("Edit photos like we're back in the 2000s")
        subtitleLabel.font = UIFont(name: "MSW98UI-Regular", size: 14) ?? .systemFont(ofSize: 14)
        subtitleLabel.textColor = UIColor.y2kInk.withAlphaComponent(0.65)
        subtitleLabel.numberOfLines = 2
        subtitleLabel.textAlignment = .center

        uploadButton.setTitle(Y2KString("Tap to Upload Photo"), for: .normal)
        style(primary: uploadButton)
        uploadButton.addTarget(self, action: #selector(pickPhoto), for: .touchUpInside)

        galleryButton.setTitle(Y2KString("Your saved photos :)"), for: .normal)
        style(primary: galleryButton)
        galleryButton.addTarget(self, action: #selector(openGallery), for: .touchUpInside)

        settingsButton.setTitle(Y2KString("Settings"), for: .normal)
        style(primary: settingsButton)
        settingsButton.addTarget(self, action: #selector(openSettings), for: .touchUpInside)

        let header = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        header.axis = .vertical
        header.spacing = 6
        header.translatesAutoresizingMaskIntoConstraints = false

        let buttons = UIStackView(arrangedSubviews: [uploadButton, galleryButton, settingsButton])
        buttons.axis = .vertical
        buttons.spacing = 12
        buttons.translatesAutoresizingMaskIntoConstraints = false

        recentStack.axis = .horizontal
        recentStack.spacing = 8
        recentStack.alignment = .center
        recentStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(header)
        view.addSubview(buttons)
        view.addSubview(recentStack)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 48),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            buttons.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            buttons.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            buttons.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            recentStack.topAnchor.constraint(equalTo: buttons.bottomAnchor, constant: 24),
            recentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            recentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            recentStack.heightAnchor.constraint(equalToConstant: 64)
        ])
    }

    private func style(primary button: UIButton) {
        button.titleLabel?.font = UIFont(name: "MSW98UI-Bold", size: 17) ?? .boldSystemFont(ofSize: 17)
        button.setTitleColor(.y2kInk, for: .normal)
        button.backgroundColor = UIColor.white
        button.layer.cornerRadius = 14
        button.layer.borderWidth = 1.5
        button.layer.borderColor = UIColor.y2kInk.withAlphaComponent(0.25).cgColor
        button.heightAnchor.constraint(equalToConstant: 52).isActive = true
    }

    private func reloadRecent() {
        recentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let items = GalleryManager.shared.images().prefix(4)
        if items.isEmpty { return }
        for item in items {
            let iv = UIImageView(image: item.image)
            iv.contentMode = .scaleAspectFill
            iv.clipsToBounds = true
            iv.layer.cornerRadius = 10
            iv.layer.borderWidth = 1
            iv.layer.borderColor = UIColor.y2kInk.withAlphaComponent(0.15).cgColor
            iv.widthAnchor.constraint(equalToConstant: 56).isActive = true
            iv.heightAnchor.constraint(equalToConstant: 56).isActive = true
            recentStack.addArrangedSubview(iv)
        }
        let spacer = UIView()
        recentStack.addArrangedSubview(spacer)
    }

    // MARK: Actions

    @objc private func pickPhoto() {
        Haptics.tap()
        if #available(iOS 14.0, *) {
            let picker = PHPickerViewController(configuration: {
                var config = PHPickerConfiguration()
                config.filter = .images
                config.selectionLimit = 1
                return config
            }())
            picker.delegate = self
            present(picker, animated: true)
        } else {
            // iOS 12/13 path: UIImagePickerController.
            guard UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else {
                y2kAlert(title: Y2KString("Error"),
                         message: Y2KString("Unable to save image to photo library."))
                return
            }
            let picker = UIImagePickerController()
            picker.sourceType = .photoLibrary
            picker.delegate = self
            present(picker, animated: true)
        }
    }

    @objc private func openGallery() {
        Haptics.tap()
        navigationController?.pushViewController(GalleryViewController(), animated: true)
    }

    @objc private func openSettings() {
        Haptics.tap()
        navigationController?.pushViewController(SettingsViewController(), animated: true)
    }

    private func openEditor(with image: UIImage) {
        let editor = EditorViewController(image: image)
        navigationController?.pushViewController(editor, animated: true)
    }
}

// MARK: - Pickers

extension HomeViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true) {
            if let image = info[.originalImage] as? UIImage {
                self.openEditor(with: image)
            }
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

@available(iOS 14.0, *)
extension HomeViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider,
              provider.canLoadObject(ofClass: UIImage.self) else { return }
        provider.loadObject(ofClass: UIImage.self) { object, _ in
            guard let image = object as? UIImage else { return }
            DispatchQueue.main.async { self.openEditor(with: image) }
        }
    }
}
