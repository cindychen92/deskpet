import Cocoa
import UniformTypeIdentifiers

final class PetSettingsWindowController: NSWindowController, NSTextFieldDelegate {
    private let resourceService: FirebasePetResourceService
    private let onUploaded: (PetMetadata) -> Void
    private let nameField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let uploadButton = NSButton()
    private let resourcesLabel = NSTextField(labelWithString: "")
    private var selectedFiles: [String: URL] = [:]
    private var resourceStatusLabels: [String: NSTextField] = [:]
    private var resourceStatusIcons: [String: NSImageView] = [:]
    private var selectionButtons: [String: NSButton] = [:]
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
        window.title = L10n.text("settings.window.title")
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
        panel.message = L10n.format("settings.file_picker.message", displayName)

        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            guard
                url.pathExtension.lowercased() == "png",
                NSImage(contentsOf: url) != nil
            else {
                self.showStatus(
                    L10n.format("error.resource.invalid_png", displayName),
                    isError: true
                )
                return
            }

            self.selectedFiles[resourceName] = url
            self.updateSelectionState(for: resourceName, fileURL: url)
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
            showStatus(L10n.text("settings.error.select_all_images"), isError: true)
            return
        }

        setUploading(true)
        showStatus(L10n.format("settings.status.uploading_pet", petName), isError: false)
        resourceService.uploadPet(named: petName, files: selectedFiles) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.setUploading(false)
                switch result {
                case .success(let pet):
                    self.showStatus(
                        L10n.format("settings.status.upload_complete", pet.name),
                        isError: false
                    )
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

        let titleLabel = NSTextField(labelWithString: L10n.text("settings.heading"))
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)

        let nameLabel = NSTextField(labelWithString: L10n.text("settings.pet_name.label"))
        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameField.placeholderString = L10n.text("settings.pet_name.placeholder")
        nameField.delegate = self

        let nameStack = NSStackView(views: [nameLabel, nameField])
        nameStack.orientation = .horizontal
        nameStack.alignment = .centerY
        nameStack.spacing = 14
        nameLabel.setContentHuggingPriority(.required, for: .horizontal)

        resourcesLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        updateResourcesLabel()

        let resourcesStack = NSStackView()
        resourcesStack.orientation = .vertical
        resourcesStack.alignment = .leading
        resourcesStack.spacing = 7

        for requirement in PetResourceManifest.requiredImages {
            let resourceName = requirement.fileName
            let fileLabel = NSTextField(labelWithString: requirement.displayName)
            fileLabel.font = .systemFont(ofSize: 13, weight: .regular)
            fileLabel.widthAnchor.constraint(equalToConstant: 155).isActive = true

            let statusIcon = NSImageView(
                image: NSImage(
                    systemSymbolName: "circle",
                    accessibilityDescription: L10n.text("accessibility.resource.not_selected")
                ) ?? NSImage()
            )
            statusIcon.contentTintColor = .tertiaryLabelColor
            statusIcon.symbolConfiguration = .init(pointSize: 13, weight: .medium)
            statusIcon.widthAnchor.constraint(equalToConstant: 18).isActive = true
            statusIcon.heightAnchor.constraint(equalToConstant: 18).isActive = true
            resourceStatusIcons[resourceName] = statusIcon

            let selectedLabel = NSTextField(
                labelWithString: L10n.text("settings.resource.not_selected")
            )
            selectedLabel.lineBreakMode = .byTruncatingMiddle
            selectedLabel.textColor = .secondaryLabelColor
            selectedLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            resourceStatusLabels[resourceName] = selectedLabel

            let button = NSButton(
                title: L10n.text("settings.resource.choose"),
                target: self,
                action: #selector(chooseImage(_:))
            )
            button.identifier = NSUserInterfaceItemIdentifier(resourceName)
            button.image = NSImage(
                systemSymbolName: "folder",
                accessibilityDescription: L10n.text("accessibility.resource.choose_image")
            )
            button.imagePosition = .imageLeading
            button.bezelStyle = .rounded
            button.widthAnchor.constraint(equalToConstant: 92).isActive = true
            selectionButtons[resourceName] = button

            let row = NSStackView(views: [fileLabel, statusIcon, selectedLabel, button])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 12
            resourcesStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: resourcesStack.widthAnchor).isActive = true
        }

        statusLabel.maximumNumberOfLines = 2
        statusLabel.lineBreakMode = .byWordWrapping

        uploadButton.title = L10n.text("settings.upload")
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

    private func updateSelectionState(for resourceName: String, fileURL: URL?) {
        let isSelected = fileURL != nil
        resourceStatusLabels[resourceName]?.stringValue = fileURL?.lastPathComponent
            ?? L10n.text("settings.resource.not_selected")
        resourceStatusLabels[resourceName]?.textColor = isSelected ? .labelColor : .secondaryLabelColor

        let iconName = isSelected ? "checkmark.circle.fill" : "circle"
        resourceStatusIcons[resourceName]?.image = NSImage(
            systemSymbolName: iconName,
            accessibilityDescription: isSelected
                ? L10n.text("accessibility.resource.selected")
                : L10n.text("accessibility.resource.not_selected")
        )
        resourceStatusIcons[resourceName]?.contentTintColor = isSelected ? .systemGreen : .tertiaryLabelColor

        selectionButtons[resourceName]?.title = isSelected
            ? L10n.text("settings.resource.replace")
            : L10n.text("settings.resource.choose")
        updateResourcesLabel()
    }

    private func updateResourcesLabel() {
        resourcesLabel.stringValue = L10n.format(
            "settings.resources.progress",
            L10n.integer(selectedFiles.count),
            L10n.integer(PetResourceManifest.requiredImages.count)
        )
    }

    private func setUploading(_ uploading: Bool) {
        isUploading = uploading
        nameField.isEnabled = !uploading
        selectionButtons.values.forEach { $0.isEnabled = !uploading }
        uploadButton.title = uploading
            ? L10n.text("settings.upload.in_progress")
            : L10n.text("settings.upload")
        updateUploadButton()
    }

    private func clearSelectedFiles() {
        selectedFiles.removeAll()
        for resourceName in PetResourceManifest.requiredImageNames {
            updateSelectionState(for: resourceName, fileURL: nil)
        }
        updateUploadButton()
    }

    private func showStatus(_ message: String, isError: Bool) {
        statusLabel.stringValue = message
        statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }
}
