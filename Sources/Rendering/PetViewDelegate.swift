import Cocoa

protocol PetViewDelegate: AnyObject {
    func petWasTapped()
    func petWasDragged(to origin: NSPoint)
    func showPetMenu(for event: NSEvent)
}
