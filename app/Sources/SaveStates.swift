import AppKit

/// Sauvegardes d'état : quatre emplacements par jeu, chacun avec son image et sa date (comme la version Android)
enum SaveStates {
    static var dir: URL { Paths.dir("etats") }
    static func key(_ game: String) -> String {
        ((game as NSString).deletingPathExtension).replacingOccurrences(of: "/", with: "_")
    }
    static func state(_ game: String, _ slot: Int) -> URL { dir.appendingPathComponent("\(key(game))-\(slot + 1).uss") }
    static func thumb(_ game: String, _ slot: Int) -> URL { dir.appendingPathComponent("\(key(game))-\(slot + 1).jpg") }

    static func save(_ game: String, _ slot: Int) -> Bool {
        let ok = amb_save_state(state(game, slot).path) != 0
        if ok, let img = Captures.frame() { _ = Captures.write(img, to: thumb(game, slot), type: .jpeg, maxWidth: 320) }
        return ok
    }
    static func load(_ game: String, _ slot: Int) -> Bool {
        let f = state(game, slot)
        return FileManager.default.fileExists(atPath: f.path) && amb_load_state(f.path) != 0
    }
}

/// Fenêtre des emplacements : l'image de chacun, sa date, « Sauvegarder » et « Reprendre »
final class SaveStatesPanel: NSObject {
    private var panel: NSPanel?
    private let game: String
    private let done: (String) -> Void

    init(game: String, done: @escaping (String) -> Void) { self.game = game; self.done = done }

    func show(over window: NSWindow) {
        let col = NSStackView()
        col.orientation = .vertical; col.alignment = .leading; col.spacing = 10
        col.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        let title = NSTextField(labelWithString: "Sauvegardes d'état : " + SaveStates.key(game))
        title.font = .boldSystemFont(ofSize: 14)
        col.addArrangedSubview(title)
        let fmt = DateFormatter(); fmt.locale = Locale(identifier: "fr_FR"); fmt.dateFormat = "dd/MM/yyyy HH:mm"
        for slot in 0..<4 {
            let img = NSImageView()
            img.imageScaling = .scaleProportionallyUpOrDown
            img.image = NSImage(contentsOf: SaveStates.thumb(game, slot))
            img.translatesAutoresizingMaskIntoConstraints = false
            img.widthAnchor.constraint(equalToConstant: 96).isActive = true
            img.heightAnchor.constraint(equalToConstant: 72).isActive = true
            let f = SaveStates.state(game, slot)
            let date = (try? FileManager.default.attributesOfItem(atPath: f.path)[.modificationDate] as? Date).map { fmt.string(from: $0) }
            let label = NSTextField(labelWithString: "Emplacement \(slot + 1)\n" + (date ?? "vide"))
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(equalToConstant: 150).isActive = true
            let save = ClosureButton("Sauvegarder") { [self] in
                done(SaveStates.save(game, slot) ? "État \(slot + 1) sauvegardé" : "Sauvegarde impossible"); close()
            }
            let load = ClosureButton("Reprendre") { [self] in
                done(SaveStates.load(game, slot) ? "État \(slot + 1) repris" : "Aucun état à reprendre"); close()
            }
            load.isEnabled = date != nil
            let r = NSStackView(views: [img, label, save, load]); r.orientation = .horizontal; r.spacing = 10
            col.addArrangedSubview(r)
        }
        col.addArrangedSubview(ClosureButton("Fermer") { [self] in close() })
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 420), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        p.title = "Sauvegardes d'état"
        p.contentView = col
        panel = p
        window.beginSheet(p)
    }

    private func close() {
        guard let p = panel else { return }
        p.sheetParent?.endSheet(p)
        panel = nil
    }
}
