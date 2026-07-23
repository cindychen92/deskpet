import Cocoa

enum PetMenuBuilder {
    static func makeMenu(target: AnyObject, walkEnabled: Bool) -> NSMenu {
        let menu = NSMenu()
        addMenuItem("普通", action: #selector(AppDelegate.setNormal), target: target, to: menu)
        addMenuItem("趴下", action: #selector(AppDelegate.setLie), target: target, to: menu)
        addMenuItem("睡觉", action: #selector(AppDelegate.setSleep), target: target, to: menu)
        addMenuItem("吃饭", action: #selector(AppDelegate.setEat), target: target, to: menu)
        addMenuItem("撒娇", action: #selector(AppDelegate.setCuddle), target: target, to: menu)
        menu.addItem(.separator())
        addMenuItem("摇头", action: #selector(AppDelegate.shakeAction), target: target, to: menu)
        addMenuItem("跳一跳", action: #selector(AppDelegate.jumpAction), target: target, to: menu)
        let walkTitle = walkEnabled ? "暂停边缘走动" : "继续边缘走动"
        addMenuItem(walkTitle, action: #selector(AppDelegate.toggleWalk), target: target, to: menu)
        menu.addItem(.separator())
        addMenuItem("退出桌宠", action: #selector(AppDelegate.quit), target: target, to: menu)
        return menu
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
