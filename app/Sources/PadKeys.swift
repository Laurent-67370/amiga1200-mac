import AppKit

/// Boutons de manette changés en touches du clavier Amiga, pour un jeu (comme la version Android) : la barre d'espace
/// d'un jeu, F1 pour choisir le nombre de joueurs, Return pour la carte…
enum PadKeys {
    /// Boutons réglables (A et B restent les deux boutons de tir)
    static let buttons = ["X", "Y", "L1", "R1", "L2", "R2", "L3", "R3", "Menu", "Options"]

    /// Touches proposées (codes RETROK du cœur) ; 0 : le bouton reste un bouton de manette
    static let keys: [(Int, String)] = [
        (0, "Manette (par défaut)"), (32, "Espace"), (13, "Return"), (27, "Échap"), (127, "Del"), (8, "Retour arrière"),
        (281, "Help"), (9, "Tab"), (304, "Maj"), (306, "Ctrl"), (308, "Alt"), (311, "Amiga gauche"), (312, "Amiga droite"),
        (273, "↑"), (274, "↓"), (276, "←"), (275, "→"), (268, "* (pavé)"),
    ] + (1...10).map { (281 + $0, "F\($0)") } + (1...9).map { (48 + $0, "\($0)") } + [(48, "0")] +
        "ynpqmsjc".map { (Int($0.asciiValue!), $0.uppercased()) }

    private static let d = UserDefaults.standard

    /// Réglage d'un jeu : bouton → touche
    static func load(_ game: String) -> [String: Int] {
        ((d.dictionary(forKey: "touches") ?? [:])[game] as? [String: Int] ?? [:]).filter { $0.value != 0 }
    }
    static func save(_ game: String, _ map: [String: Int]) {
        var all = d.dictionary(forKey: "touches") ?? [:]
        let m = map.filter { $0.value != 0 }
        all[game] = m.isEmpty ? nil : m
        d.set(all, forKey: "touches")
    }

    /// Fenêtre de réglage : une liste de touches par bouton
    static func dialog(game: String, title: String) -> [String: Int]? {
        let cur = load(game)
        let grid = NSGridView()
        grid.rowSpacing = 6; grid.columnSpacing = 10
        var popups: [NSPopUpButton] = []
        for b in buttons {
            let p = NSPopUpButton()
            p.addItems(withTitles: keys.map(\.1))
            p.selectItem(at: keys.firstIndex { $0.0 == cur[b] ?? 0 } ?? 0)
            popups.append(p)
            grid.addRow(with: [NSTextField(labelWithString: b), p])
        }
        grid.frame = NSRect(x: 0, y: 0, width: 300, height: CGFloat(buttons.count) * 32)
        let a = NSAlert()
        a.messageText = "Touches de la manette : \(title)"
        a.informativeText = "A et B restent les boutons de tir, la croix et le stick le joystick. Les autres boutons peuvent taper une touche du clavier Amiga, pour ce jeu seulement."
        a.accessoryView = grid
        a.addButton(withTitle: "Enregistrer"); a.addButton(withTitle: "Annuler")
        guard a.runModal() == .alertFirstButtonReturn else { return nil }
        var m: [String: Int] = [:]
        for (i, b) in buttons.enumerated() { m[b] = keys[max(popups[i].indexOfSelectedItem, 0)].0 }
        save(game, m)
        return load(game)
    }
}
