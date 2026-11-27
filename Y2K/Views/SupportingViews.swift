//
//  SupportingViews.swift
//  y2k
//
//  Gallery, settings and the shared image helpers used by the editor.
//

import UIKit

// MARK: - Image helpers

extension UIImage {
    /// Downscales for the live preview; keeps orientation.
    func y2k_thumbnail(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height) * scale
        guard longest > maxDimension else { return self }
        let ratio = maxDimension / longest
        let target = CGSize(width: size.width * ratio, height: size.height * ratio)
        UIGraphicsBeginImageContextWithOptions(target, false, 1.0)
        draw(in: CGRect(origin: .zero, size: target))
        let result = UIGraphicsGetImageFromCurrentImageContext() ?? self
        UIGraphicsEndImageContext()
        return result
    }

    func y2k_rotated() -> UIImage? {
        guard let cg = cgImage else { return nil }
        let size = CGSize(width: cg.height, height: cg.width)
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        guard let ctx = UIGraphicsGetCurrentContext() else { return nil }
        ctx.translateBy(x: size.width / 2, y: size.height / 2)
        ctx.rotate(by: .pi / 2)
        ctx.draw(cg, in: CGRect(x: -CGFloat(cg.width) / 2, y: -CGFloat(cg.height) / 2,
                                width: CGFloat(cg.width), height: CGFloat(cg.height)))
        let rotated = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return rotated
    }
}

// MARK: - Premium gate

/// The original gates filters/stickers behind "y2k plus". StoreKit is stripped
/// from this build (no receipt to validate on a sideloaded app), so the gate is
/// a local toggle that defaults to unlocked — see README.
enum PremiumGate {
    private static let key = "y2k_plus_unlocked"

    static var isUnlocked: Bool {
        get {
            if UserDefaults.standard.object(forKey: key) == nil { return true }
            return UserDefaults.standard.bool(forKey: key)
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

// MARK: - Gallery

final class GalleryViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    private var items: [(name: String, image: UIImage)] = []
    private var collection: UICollectionView!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .y2kCream
        title = Y2KString("Your saved photos :)")
        navigationItem.backBarButtonItem = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)

        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.sectionInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        collection = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collection.backgroundColor = .clear
        collection.dataSource = self
        collection.delegate = self
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        collection.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(collection)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        items = GalleryManager.shared.images()
        collection.reloadData()
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return items.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }
        let iv = UIImageView(image: items[indexPath.item].image)
        iv.frame = cell.contentView.bounds
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 8
        iv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cell.contentView.addSubview(iv)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = (collectionView.bounds.width - 32) / 3
        return CGSize(width: width, height: width * 1.25)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let item = items[indexPath.item]
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: Y2KString("Share"), style: .default) { _ in
            let source = Y2KActivityItemSource(image: item.image)
            let share = UIActivityViewController(activityItems: [source], applicationActivities: nil)
            if let pop = share.popoverPresentationController {
                pop.sourceView = collectionView.cellForItem(at: indexPath)
                pop.sourceRect = collectionView.cellForItem(at: indexPath)?.bounds ?? .zero
            }
            self.present(share, animated: true)
        })
        alert.addAction(UIAlertAction(title: Y2KString("Delete"), style: .destructive) { _ in
            GalleryManager.shared.delete(named: item.name)
            self.items = GalleryManager.shared.images()
            collectionView.reloadData()
        })
        alert.addAction(UIAlertAction(title: Y2KString("Cancel"), style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.sourceView = collectionView.cellForItem(at: indexPath)
            pop.sourceRect = collectionView.cellForItem(at: indexPath)?.bounds ?? .zero
        }
        present(alert, animated: true)
    }
}

// MARK: - Settings

final class SettingsViewController: UITableViewController {

    private let rows: [(String, String)] = [
        (Y2KString("Language"), "language"),
        (Y2KString("Unlock All Effects"), "plus"),
        (Y2KString("Restore"), "restore"),
        (Y2KString("Send Us Feedback"), "feedback"),
        (Y2KString("Privacy Policy"), "privacy"),
        (Y2KString("Terms of Use"), "terms"),
        (Y2KString("Version"), "version")
    ]

    init() {
        super.init(style: .grouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = Y2KString("Settings")
        tableView.backgroundColor = .y2kCream
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { return 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return rows.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        let row = rows[indexPath.row]
        cell.textLabel?.text = row.0
        cell.textLabel?.font = UIFont(name: "MSW98UI-Regular", size: 16) ?? .systemFont(ofSize: 16)
        cell.backgroundColor = .white
        if row.1 == "language" {
            cell.detailTextLabel?.text = AppLanguageManager.shared.currentCode
        } else if row.1 == "version" {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.03"
            cell.detailTextLabel?.text = "\(version) (iOS 12 clone)"
        } else if row.1 == "plus" {
            cell.detailTextLabel?.text = PremiumGate.isUnlocked ? "✓" : ""
        }
        cell.accessoryType = (row.1 == "privacy" || row.1 == "terms" || row.1 == "feedback") ? .disclosureIndicator : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch rows[indexPath.row].1 {
        case "language":
            presentLanguagePicker()
        case "plus":
            PremiumGate.isUnlocked = true
            tableView.reloadData()
            y2kAlert(title: Y2KString("Unlock All Effects"),
                     message: Y2KString("Unlock ALL filters and sticker effects"))
        case "restore":
            y2kAlert(title: Y2KString("Restore"),
                     message: Y2KString("No previous purchases found to restore"))
        case "feedback":
            open("mailto:support@y2kapp.com?subject=Feedback%20on%20y2k")
        case "privacy":
            open("https://www.y2kapp.com/privacy-policy")
        case "terms":
            open("https://www.y2kapp.com/terms-of-service")
        default:
            break
        }
    }

    private func presentLanguagePicker() {
        let sheet = UIAlertController(title: Y2KString("Language"), message: nil, preferredStyle: .actionSheet)
        for language in AppLanguageManager.shared.available {
            sheet.addAction(UIAlertAction(title: "\(language.endonym)  ·  \(language.englishName)",
                                          style: .default) { _ in
                AppLanguageManager.shared.currentCode = language.code
                self.tableView.reloadData()
            })
        }
        sheet.addAction(UIAlertAction(title: Y2KString("Cancel"), style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        present(sheet, animated: true)
    }

    private func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}
