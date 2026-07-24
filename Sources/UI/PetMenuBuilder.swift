import Cocoa

enum PetMenuBuilder {
    static func makeMenu(
        target: AnyObject,
        walkEnabled: Bool,
        pets: [PetMetadata],
        activePetId: String
    ) -> NSMenu {
        let menu = NSMenu()
        addMenuItem(L10n.text("menu.action.normal"), action: #selector(AppDelegate.setNormal), target: target, to: menu)
        addMenuItem(L10n.text("menu.action.lie"), action: #selector(AppDelegate.setLie), target: target, to: menu)
        addMenuItem(L10n.text("menu.action.sleep"), action: #selector(AppDelegate.setSleep), target: target, to: menu)
        addMenuItem(L10n.text("menu.action.eat"), action: #selector(AppDelegate.setEat), target: target, to: menu)
        addMenuItem(L10n.text("menu.action.cuddle"), action: #selector(AppDelegate.setCuddle), target: target, to: menu)
        menu.addItem(.separator())
        addMenuItem(L10n.text("menu.action.shake"), action: #selector(AppDelegate.shakeAction), target: target, to: menu)
        addMenuItem(L10n.text("menu.action.jump"), action: #selector(AppDelegate.jumpAction), target: target, to: menu)
        let walkTitle = walkEnabled
            ? L10n.text("menu.walk.pause")
            : L10n.text("menu.walk.resume")
        addMenuItem(walkTitle, action: #selector(AppDelegate.toggleWalk), target: target, to: menu)
        menu.addItem(.separator())
        addMenuItem(L10n.text("menu.pet_settings"), action: #selector(AppDelegate.showPetSettings), target: target, to: menu)
        addPetSelectionItems(
            pets,
            activePetId: activePetId,
            target: target,
            to: menu
        )
        menu.addItem(.separator())
        addMenuItem(L10n.text("menu.quit"), action: #selector(AppDelegate.quit), target: target, to: menu)
        return menu
    }

    private static func addPetSelectionItems(
        _ pets: [PetMetadata],
        activePetId: String,
        target: AnyObject,
        to menu: NSMenu
    ) {
        let petsMenu = NSMenu()
        for pet in pets {
            let title = pet.requiredImagesComplete
                ? pet.name
                : L10n.format("menu.pet.incomplete", pet.name)
            let item = NSMenuItem(
                title: title,
                action: #selector(AppDelegate.selectPetFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = target
            item.representedObject = pet.id
            item.state = pet.id == activePetId ? .on : .off
            item.isEnabled = pet.requiredImagesComplete
            petsMenu.addItem(item)
        }

        let item = NSMenuItem(title: L10n.text("menu.pet.select"), action: nil, keyEquivalent: "")
        item.submenu = petsMenu
        menu.addItem(item)
    }

    private static func addMenuItem(
        _ title: String,
        action: Selector,
        target: AnyObject,
        to menu: NSMenu
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        menu.addItem(item)
    }
}
