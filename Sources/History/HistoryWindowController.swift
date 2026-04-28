import AppKit

final class HistoryWindowController: NSWindowController, NSCollectionViewDataSource, NSCollectionViewDelegate {

    private let collectionView = NSCollectionView()
    private let scroll = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: L10n.text(.noScreenshotsYet))

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text(.history)
        window.center()
        super.init(window: window)

        HistoryStore.shared.onChange = { [weak self] in
            DispatchQueue.main.async { self?.reload() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(languageDidChange), name: .appLanguageDidChange, object: nil)
        setupUI()
        reload()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        guard let content = window?.contentView else { return }

        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 180, height: 140)
        layout.sectionInset = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.register(HistoryCell.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("cell"))
        collectionView.backgroundColors = [NSColor.controlBackgroundColor]

        scroll.documentView = collectionView
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.textColor = .secondaryLabelColor
        content.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
    }

    private func reload() {
        window?.title = L10n.text(.history)
        emptyLabel.stringValue = L10n.text(.noScreenshotsYet)
        emptyLabel.isHidden = !HistoryStore.shared.entries.isEmpty
        collectionView.reloadData()
    }

    @objc private func languageDidChange() {
        reload()
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        HistoryStore.shared.entries.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("cell"), for: indexPath) as! HistoryCell
        let entry = HistoryStore.shared.entries[indexPath.item]
        item.configure(with: entry)
        item.onOpen = { [weak self] in
            guard let self = self, let image = HistoryStore.shared.image(for: entry) else { return }
            AppCoordinator.shared.openEditor(with: image)
            _ = self
        }
        item.onDelete = { HistoryStore.shared.delete(entry) }
        return item
    }
}

final class HistoryCell: NSCollectionViewItem {
    var onOpen: (() -> Void)?
    var onDelete: (() -> Void)?

    private let imgView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let deleteBtn = NSButton()
    private let openBtn = NSButton()

    override func loadView() {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 180, height: 140))
        v.wantsLayer = true
        v.layer?.cornerRadius = 6
        v.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        v.layer?.borderWidth = 1
        v.layer?.borderColor = NSColor.separatorColor.cgColor
        view = v

        imgView.translatesAutoresizingMaskIntoConstraints = false
        imgView.imageScaling = .scaleProportionallyUpOrDown
        v.addSubview(imgView)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 10)
        label.textColor = .secondaryLabelColor
        v.addSubview(label)

        openBtn.title = L10n.text(.open)
        openBtn.bezelStyle = .inline
        openBtn.target = self
        openBtn.action = #selector(openTap)
        openBtn.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(openBtn)

        deleteBtn.title = L10n.text(.delete)
        deleteBtn.bezelStyle = .inline
        deleteBtn.target = self
        deleteBtn.action = #selector(deleteTap)
        deleteBtn.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(deleteBtn)

        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(openTap))
        doubleClick.numberOfClicksRequired = 2
        v.addGestureRecognizer(doubleClick)

        NSLayoutConstraint.activate([
            imgView.topAnchor.constraint(equalTo: v.topAnchor, constant: 6),
            imgView.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 6),
            imgView.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -6),
            imgView.heightAnchor.constraint(equalToConstant: 90),

            label.topAnchor.constraint(equalTo: imgView.bottomAnchor, constant: 4),
            label.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -6),

            openBtn.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -4),
            openBtn.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 6),
            deleteBtn.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -4),
            deleteBtn.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -6),
        ])
    }

    func configure(with entry: HistoryEntry) {
        openBtn.title = L10n.text(.open)
        deleteBtn.title = L10n.text(.delete)
        imgView.image = HistoryStore.shared.image(for: entry)
        let df = DateFormatter()
        df.dateStyle = .short; df.timeStyle = .short
        label.stringValue = df.string(from: entry.timestamp)
    }

    @objc private func openTap() { onOpen?() }
    @objc private func deleteTap() { onDelete?() }
}
