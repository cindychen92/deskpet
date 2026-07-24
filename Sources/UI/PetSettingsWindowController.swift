import Cocoa
import UniformTypeIdentifiers

final class PetSettingsWindowController: NSWindowController, NSTextFieldDelegate {
    private let resourceService: FirebasePetResourceService
    private let onUploaded: (PetMetadata) -> Void
    private let nameField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let uploadButton = NSButton()
    private var selectedFiles: [String: URL] = [:]
    private var resourceStatusLabels: [String: NSTextField] = [:]
    private var selectionButtons: [NSButton] = []
    private var isUploading = false

    init(
        resourceService: FirebasePetResourceService,
        onUploaded: @escaping (PetMetadata) -> Void
    ) {
        self.resourceService = resourceService
        self.onUploaded = onUploaded
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 570),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = "宠物设置"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentViewController = makeContentViewController()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    func controlTextDidChange(_ notification: Notification) {
        statusLabel.stringValue = ""
        updateUploadButton()
    }

    @objc private func chooseImage(_ sender: NSButton) {
        guard let resourceName = sender.identifier?.rawValue, let window else { return }
        let displayName = PetResourceManifest.displayName(for: resourceName)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "选择“\(displayName)”图片"

        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            guard
                url.pathExtension.lowercased() == "png",
                NSImage(contentsOf: url) != nil
            else {
                self.showStatus("“\(displayName)”必须是可读取的 PNG 图片。", isError: true)
                return
            }

            self.selectedFiles[resourceName] = url
            self.resourceStatusLabels[resourceName]?.stringValue = url.lastPathComponent
            self.resourceStatusLabels[resourceName]?.textColor = .labelColor
            self.statusLabel.stringValue = ""
            self.updateUploadButton()
        }
    }

    @objc private func uploadPet() {
        let petName: String
        switch PetResourceManifest.validatedPetName(nameField.stringValue) {
        case .success(let name):
            petName = name
        case .failure(let error):
            showStatus(error.localizedDescription, isError: true)
            return
        }

        let missingNames = PetResourceManifest.requiredImageNames.filter { selectedFiles[$0] == nil }
        guard missingNames.isEmpty else {
            showStatus("请先选择全部必需图片。", isError: true)
            return
        }

        setUploading(true)
        showStatus("正在上传 \(petName)…", isError: false)
        resourceService.uploadPet(named: petName, files: selectedFiles) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.setUploading(false)
                switch result {
                case .success(let pet):
                    self.showStatus("\(pet.name) 上传完成，已切换为当前宠物。", isError: false)
                    self.onUploaded(pet)
                    self.clearSelectedFiles()
                case .failure(let error):
                    self.showStatus(error.localizedDescription, isError: true)
                }
            }
        }
    }

    private func makeContentViewController() -> NSViewController {
        let viewController = NSViewController()
        let contentView = NSView()
        viewController.view = contentView

        let titleLabel = NSTextField(labelWithString: "管理宠物资源")
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)

        let nameLabel = NSTextField(labelWithString: "宠物名称")
        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameField.placeholderString = "例如：Ginger、我的小狗、🐶"
        nameField.delegate = self

        let nameStack = NSStackView(views: [nameLabel, nameField])
        nameStack.orientation = .horizontal
        nameStack.alignment = .centerY
        nameStack.spacing = 14
        nameLabel.setContentHuggingPriority(.required, for: .horizontal)

        let resourcesLabel = NSTextField(labelWithString: "必需图片")
        resourcesLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        let resourcesStack = NSStackView()
        resourcesStack.orientation = .vertical
        resourcesStack.alignment = .leading
        resourcesStack.spacing = 7

        for requirement in PetResourceManifest.requiredImages {
            let resourceName = requirement.fileName
            let fileLabel = NSTextField(labelWithString: requirement.displayName)
            fileLabel.font = .systemFont(ofSize: 13, weight: .regular)
            fileLabel.widthAnchor.constraint(equalToConstant: 155).isActive = true

            let selectedLabel = NSTextField(labelWithString: "尚未选择")
            selectedLabel.lineBreakMode = .byTruncatingMiddle
            selectedLabel.textColor = .secondaryLabelColor
            selectedLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            resourceStatusLabels[resourceName] = selectedLabel

            let button = NSButton(
                title: "选择…",
                target: self,
                action: #selector(chooseImage(_:))
            )
            button.identifier = NSUserInterfaceItemIdentifier(resourceName)
            button.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "选择图片")
            button.imagePosition = .imageLeading
            button.bezelStyle = .rounded
            selectionButtons.append(button)

            let row = NSStackView(views: [fileLabel, selectedLabel, button])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 12
            resourcesStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: resourcesStack.widthAnchor).isActive = true
        }

        statusLabel.maximumNumberOfLines = 2
        statusLabel.lineBreakMode = .byWordWrapping

        uploadButton.title = "上传并使用"
        uploadButton.target = self
        uploadButton.action = #selector(uploadPet)
        uploadButton.bezelStyle = .rounded
        uploadButton.keyEquivalent = "\r"

        let actionStack = NSStackView(views: [statusLabel, uploadButton])
        actionStack.orientation = .horizontal
        actionStack.alignment = .centerY
        actionStack.spacing = 16
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        uploadButton.setContentHuggingPriority(.required, for: .horizontal)

        let rootStack = NSStackView(views: [
            titleLabel,
            nameStack,
            resourcesLabel,
            resourcesStack,
            actionStack
        ])
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 16
        rootStack.setCustomSpacing(22, after: titleLabel)
        rootStack.setCustomSpacing(20, after: nameStack)
        rootStack.setCustomSpacing(10, after: resourcesLabel)
        contentView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -24),
            nameStack.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            resourcesStack.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            actionStack.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            statusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 36)
        ])

        updateUploadButton()
        return viewController
    }

    private func updateUploadButton() {
        let hasValidName: Bool
        switch PetResourceManifest.validatedPetName(nameField.stringValue) {
        case .success:
            hasValidName = true
        case .failure:
            hasValidName = false
        }
        let hasAllImages = PetResourceManifest.requiredImageNames.allSatisfy {
            selectedFiles[$0] != nil
        }
        uploadButton.isEnabled = hasValidName && hasAllImages && !isUploading
    }

    private func setUploading(_ uploading: Bool) {
        isUploading = uploading
        nameField.isEnabled = !uploading
        selectionButtons.forEach { $0.isEnabled = !uploading }
        uploadButton.title = uploading ? "正在上传…" : "上传并使用"
        updateUploadButton()
    }

    private func clearSelectedFiles() {
        selectedFiles.removeAll()
        for label in resourceStatusLabels.values {
            label.stringValue = "尚未选择"
            label.textColor = .secondaryLabelColor
        }
        updateUploadButton()
    }

    private func showStatus(_ message: String, isError: Bool) {
        statusLabel.stringValue = message
        statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }
}
