import Cocoa
import UniformTypeIdentifiers

final class PetSettingsWindowController: NSWindowController, NSTextFieldDelegate {
    private let resourceService: FirebasePetResourceService
    private let onUploaded: (PetMetadata) -> Void
    private let onRenamed: (PetMetadata) -> Void
    private let onDeleted: (PetMetadata) -> Void
    private let nameField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let uploadButton = NSButton()
    private let resourcesLabel = NSTextField(labelWithString: "")
    private var selectedFiles: [String: URL] = [:]
    private var resourceStatusLabels: [String: NSTextField] = [:]
    private var resourceStatusIcons: [String: NSImageView] = [:]
    private var selectionButtons: [String: NSButton] = [:]
    private var isUploading = false
    private var managedPets: [PetMetadata] = []
    private var activePetId = PetMetadata.defaultSimba.id
    private var accountState: PetAccountState = .unavailable

    init(
        resourceService: FirebasePetResourceService,
        onUploaded: @escaping (PetMetadata) -> Void,
        onRenamed: @escaping (PetMetadata) -> Void,
        onDeleted: @escaping (PetMetadata) -> Void
    ) {
        self.resourceService = resourceService
        self.onUploaded = onUploaded
        self.onRenamed = onRenamed
        self.onDeleted = onDeleted
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 720),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = L10n.text("settings.window.title")
        window.isReleasedWhenClosed = false
        window.center()
        window.contentViewController = makeSettingsViewController()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    func updateState(
        accountState: PetAccountState,
        pets: [PetMetadata],
        activePetId: String
    ) {
        let managedPets = Self.sortedManagedPets(from: pets)
        guard
            self.accountState != accountState
                || self.managedPets != managedPets
                || self.activePetId != activePetId
        else {
            return
        }
        self.accountState = accountState
        self.managedPets = managedPets
        self.activePetId = activePetId
        window?.contentViewController = makeSettingsViewController()
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
        guard accountState.canUploadPrivatePets else {
            showStatus(L10n.text("settings.auth_required"), isError: true)
            return
        }

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
                    self.upsertManagedPet(pet)
                    self.activePetId = pet.id
                    self.clearSelectedFiles()
                    self.window?.contentViewController = self.makeSettingsViewController()
                    self.showStatus(
                        L10n.format("settings.status.upload_complete", pet.name),
                        isError: false
                    )
                    self.onUploaded(pet)
                case .failure(let error):
                    self.showStatus(error.localizedDescription, isError: true)
                }
            }
        }
    }

    @objc private func renamePet(_ sender: NSButton) {
        guard
            let pet = managedPet(for: sender),
            let window
        else {
            return
        }

        let alert = NSAlert()
        alert.messageText = L10n.format("settings.manage.rename.title", pet.name)
        alert.informativeText = L10n.text("settings.manage.rename.message")
        alert.addButton(withTitle: L10n.text("settings.manage.rename"))
        alert.addButton(withTitle: L10n.text("common.cancel"))

        let field = NSTextField(string: pet.name)
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        field.selectText(nil)
        alert.accessoryView = field

        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            self.resourceService.renamePet(pet, to: field.stringValue) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let renamedPet):
                        self.upsertManagedPet(renamedPet)
                        self.window?.contentViewController = self.makeSettingsViewController()
                        self.showStatus(
                            L10n.format("settings.status.rename_complete", renamedPet.name),
                            isError: false
                        )
                        self.onRenamed(renamedPet)
                    case .failure(let error):
                        self.showStatus(error.localizedDescription, isError: true)
                    }
                }
            }
        }
    }

    @objc private func deletePet(_ sender: NSButton) {
        guard
            let pet = managedPet(for: sender),
            let window
        else {
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.format("settings.manage.delete.title", pet.name)
        alert.informativeText = L10n.text("settings.manage.delete.message")
        alert.addButton(withTitle: L10n.text("settings.manage.delete"))
        alert.addButton(withTitle: L10n.text("common.cancel"))

        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            self.resourceService.deletePet(pet) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self.managedPets.removeAll { $0.id == pet.id }
                        if self.activePetId == pet.id {
                            self.activePetId = PetMetadata.defaultSimba.id
                        }
                        self.window?.contentViewController = self.makeSettingsViewController()
                        self.showStatus(
                            L10n.format("settings.status.delete_complete", pet.name),
                            isError: false
                        )
                        self.onDeleted(pet)
                    case .failure(let error):
                        self.showStatus(error.localizedDescription, isError: true)
                    }
                }
            }
        }
    }

    @objc private func selectLanguage(_ sender: NSPopUpButton) {
        guard
            let value = sender.selectedItem?.representedObject as? String,
            let language = AppLanguage(rawValue: value)
        else {
            return
        }

        AppLanguagePreference.current = language
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.title = L10n.text("settings.window.title")
            self.window?.contentViewController = self.makeSettingsViewController(
                selectedTabIndex: 1
            )
        }
    }

    private func makeSettingsViewController(selectedTabIndex: Int = 0) -> NSViewController {
        let tabViewController = NSTabViewController()
        tabViewController.tabStyle = .toolbar

        let resourcesTab = NSTabViewItem(viewController: makeResourcesViewController())
        resourcesTab.label = L10n.text("settings.tab.resources")
        resourcesTab.image = NSImage(
            systemSymbolName: "photo.on.rectangle",
            accessibilityDescription: resourcesTab.label
        )
        tabViewController.addTabViewItem(resourcesTab)

        let languageTab = NSTabViewItem(viewController: makeLanguageViewController())
        languageTab.label = L10n.text("settings.tab.language")
        languageTab.image = NSImage(
            systemSymbolName: "globe",
            accessibilityDescription: languageTab.label
        )
        tabViewController.addTabViewItem(languageTab)

        tabViewController.selectedTabViewItemIndex = selectedTabIndex
        return tabViewController
    }

    private func makeLanguageViewController() -> NSViewController {
        let viewController = NSViewController()
        let contentView = NSView()
        viewController.view = contentView

        let titleLabel = NSTextField(labelWithString: L10n.text("language.heading"))
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)

        let descriptionLabel = NSTextField(
            wrappingLabelWithString: L10n.text("language.description")
        )
        descriptionLabel.textColor = .secondaryLabelColor

        let languageLabel = NSTextField(labelWithString: L10n.text("language.label"))
        languageLabel.font = .systemFont(ofSize: 13, weight: .medium)

        let languagePopUp = NSPopUpButton()
        for language in AppLanguage.allCases {
            languagePopUp.addItem(withTitle: language.displayName)
            languagePopUp.lastItem?.representedObject = language.rawValue
        }
        languagePopUp.selectItem(
            withTitle: AppLanguagePreference.current.displayName
        )
        languagePopUp.target = self
        languagePopUp.action = #selector(selectLanguage(_:))

        let languageStack = NSStackView(views: [languageLabel, languagePopUp])
        languageStack.orientation = .horizontal
        languageStack.alignment = .centerY
        languageStack.spacing = 14
        languageLabel.setContentHuggingPriority(.required, for: .horizontal)

        let appliedLabel = NSTextField(
            wrappingLabelWithString: L10n.text("language.applied_immediately")
        )
        appliedLabel.textColor = .secondaryLabelColor

        let rootStack = NSStackView(views: [
            titleLabel,
            descriptionLabel,
            languageStack,
            appliedLabel
        ])
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 16
        rootStack.setCustomSpacing(10, after: titleLabel)
        rootStack.setCustomSpacing(24, after: descriptionLabel)
        contentView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            languageStack.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            languagePopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 220)
        ])

        return viewController
    }

    private func makeResourcesViewController() -> NSViewController {
        guard accountState.canUploadPrivatePets else {
            return makeAuthenticationRequiredViewController()
        }

        let viewController = NSViewController()
        let contentView = NSView()
        viewController.view = contentView
        resourceStatusLabels.removeAll()
        resourceStatusIcons.removeAll()
        selectionButtons.removeAll()

        let titleLabel = NSTextField(labelWithString: L10n.text("settings.heading"))
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)

        let managedPetsLabel = NSTextField(
            labelWithString: L10n.text("settings.manage.heading")
        )
        managedPetsLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        let managedPetsView = makeManagedPetsView()

        let separator = NSBox()
        separator.boxType = .separator

        let addPetLabel = NSTextField(labelWithString: L10n.text("settings.add.heading"))
        addPetLabel.font = .systemFont(ofSize: 13, weight: .semibold)

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
            managedPetsLabel,
            managedPetsView,
            separator,
            addPetLabel,
            nameStack,
            resourcesLabel,
            resourcesStack,
            actionStack
        ])
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 16
        rootStack.setCustomSpacing(18, after: titleLabel)
        rootStack.setCustomSpacing(8, after: managedPetsLabel)
        rootStack.setCustomSpacing(20, after: separator)
        rootStack.setCustomSpacing(10, after: addPetLabel)
        rootStack.setCustomSpacing(18, after: nameStack)
        rootStack.setCustomSpacing(10, after: resourcesLabel)
        contentView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -24),
            managedPetsView.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            separator.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            nameStack.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            resourcesStack.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            actionStack.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            statusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 36)
        ])

        updateUploadButton()
        return viewController
    }

    private func makeManagedPetsView() -> NSView {
        guard !managedPets.isEmpty else {
            let emptyLabel = NSTextField(
                wrappingLabelWithString: L10n.text("settings.manage.empty")
            )
            emptyLabel.textColor = .secondaryLabelColor
            return emptyLabel
        }

        let rows = NSStackView()
        rows.translatesAutoresizingMaskIntoConstraints = false
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 6

        for pet in managedPets {
            let nameLabel = NSTextField(labelWithString: pet.name)
            nameLabel.lineBreakMode = .byTruncatingTail
            nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            let stateLabel = NSTextField(
                labelWithString: pet.id == activePetId
                    ? L10n.text("settings.manage.current")
                    : ""
            )
            stateLabel.textColor = .secondaryLabelColor
            stateLabel.font = .systemFont(ofSize: 11)

            let nameStack = NSStackView(views: [nameLabel, stateLabel])
            nameStack.orientation = .vertical
            nameStack.alignment = .leading
            nameStack.spacing = 1

            let renameButton = NSButton(
                title: L10n.text("settings.manage.rename"),
                target: self,
                action: #selector(renamePet(_:))
            )
            renameButton.identifier = NSUserInterfaceItemIdentifier(pet.id)
            renameButton.bezelStyle = .rounded

            let deleteButton = NSButton(
                title: L10n.text("settings.manage.delete"),
                target: self,
                action: #selector(deletePet(_:))
            )
            deleteButton.identifier = NSUserInterfaceItemIdentifier(pet.id)
            deleteButton.bezelStyle = .rounded
            deleteButton.hasDestructiveAction = true

            let row = NSStackView(views: [nameStack, renameButton, deleteButton])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
            rows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = managedPets.count > 3
        scrollView.autohidesScrollers = true
        scrollView.documentView = rows

        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            rows.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            rows.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            scrollView.heightAnchor.constraint(
                equalToConstant: CGFloat(min(managedPets.count, 3) * 36)
            )
        ])
        return scrollView
    }

    private func makeAuthenticationRequiredViewController() -> NSViewController {
        let viewController = NSViewController()
        let contentView = NSView()
        viewController.view = contentView

        let imageView = NSImageView(
            image: NSImage(
                systemSymbolName: "person.crop.circle.badge.exclamationmark",
                accessibilityDescription: L10n.text("settings.auth_required.heading")
            ) ?? NSImage()
        )
        imageView.symbolConfiguration = .init(pointSize: 42, weight: .regular)
        imageView.contentTintColor = .secondaryLabelColor

        let heading = NSTextField(
            labelWithString: L10n.text("settings.auth_required.heading")
        )
        heading.font = .systemFont(ofSize: 20, weight: .semibold)

        let explanationKey = accountState == .unavailable
            ? "settings.firebase_unavailable"
            : "settings.auth_required"
        let explanation = NSTextField(
            wrappingLabelWithString: L10n.text(explanationKey)
        )
        explanation.alignment = .center
        explanation.textColor = .secondaryLabelColor
        explanation.maximumNumberOfLines = 0

        let stack = NSStackView(views: [imageView, heading, explanation])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -18),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 70),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -70),
            explanation.widthAnchor.constraint(lessThanOrEqualToConstant: 430)
        ])
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
        uploadButton.isEnabled = accountState.canUploadPrivatePets
            && hasValidName
            && hasAllImages
            && !isUploading
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

    private func managedPet(for sender: NSButton) -> PetMetadata? {
        guard let petId = sender.identifier?.rawValue else { return nil }
        return managedPets.first { $0.id == petId }
    }

    private func upsertManagedPet(_ pet: PetMetadata) {
        managedPets.removeAll { $0.id == pet.id }
        managedPets.append(pet)
        managedPets = Self.sortedManagedPets(from: managedPets)
    }

    private static func sortedManagedPets(from pets: [PetMetadata]) -> [PetMetadata] {
        pets
            .filter { !$0.isDefault && !$0.isPublic && $0.ownerUid != nil }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }
}
