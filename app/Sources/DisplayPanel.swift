import AppKit

/// Réglages de l'image pendant la partie (comme la version Android) : filtre, pixels réguliers, 4:3 ou toute la
/// fenêtre, et cadrage retenu pour ce jeu (zoom, position verticale). Tout s'applique aussitôt.
final class DisplayPanel: NSObject {
    private var panel: NSPanel?
    private let game: String
    private let changed: () -> Void
    private var zoom: Double, shift: Double
    private let zoomLabel = NSTextField(labelWithString: ""), shiftLabel = NSTextField(labelWithString: "")
    private let zoomSlider = NSSlider(), shiftSlider = NSSlider()
    private var radios: [NSButton] = []

    init(game: String, changed: @escaping () -> Void) {
        self.game = game; self.changed = changed
        zoom = Settings.shared.zoom(game); shift = Settings.shared.shiftY(game)
    }

    func show(over window: NSWindow) {
        let s = Settings.shared
        let col = NSStackView()
        col.orientation = .vertical; col.alignment = .leading; col.spacing = 8
        col.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
        let title = NSTextField(labelWithString: "Image : " + (game as NSString).deletingPathExtension)
        title.font = .boldSystemFont(ofSize: 14)
        col.addArrangedSubview(title)
        for (i, n) in ["Lisse (adoucie)", "Nette (pixels francs)", "Écran cathodique (lignes de balayage)"].enumerated() {
            let r = NSButton(radioButtonWithTitle: n, target: self, action: #selector(pickFilter(_:)))
            r.tag = i; r.state = s.filter == i ? .on : .off
            radios.append(r); col.addArrangedSubview(r)
        }
        let integer = NSButton(checkboxWithTitle: "Pixels réguliers (agrandissement en multiple entier)", target: self, action: #selector(toggleInteger(_:)))
        integer.state = s.integer ? .on : .off
        col.addArrangedSubview(integer)
        let fill = NSButton(checkboxWithTitle: "Image sur toute la fenêtre (sinon en 4:3)", target: self, action: #selector(toggleFill(_:)))
        fill.state = s.fill ? .on : .off
        col.addArrangedSubview(fill)

        let rows: [(NSTextField, NSSlider, Double, Double, Double)] = [(zoomLabel, zoomSlider, 1.0, 1.6, zoom), (shiftLabel, shiftSlider, -0.25, 0.25, shift)]
        for (label, slider, min, max, value) in rows {
            slider.minValue = min; slider.maxValue = max; slider.doubleValue = value
            slider.isContinuous = true; slider.target = self; slider.action = #selector(framing)
            slider.translatesAutoresizingMaskIntoConstraints = false
            slider.widthAnchor.constraint(equalToConstant: 320).isActive = true
            col.addArrangedSubview(label); col.addArrangedSubview(slider)
        }
        labels()
        let note = NSTextField(wrappingLabelWithString: "Le cadrage est retenu pour ce jeu : zoomez pour retirer les bandes noires, puis remontez ou descendez l'image.")
        note.font = .systemFont(ofSize: 11); note.textColor = .secondaryLabelColor; note.preferredMaxLayoutWidth = 340
        col.addArrangedSubview(note)
        let buttons = NSStackView(views: [
            ClosureButton("Cadrage d'origine") { [self] in zoomSlider.doubleValue = 1; shiftSlider.doubleValue = 0; framing() },
            ClosureButton("OK") { [self] in close() },
        ])
        buttons.spacing = 10
        col.addArrangedSubview(buttons)
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 420), styleMask: [.titled], backing: .buffered, defer: false)
        p.title = "Image"
        p.contentView = col
        panel = p
        window.beginSheet(p)
    }

    private func labels() {
        zoomLabel.stringValue = String(format: "Zoom (ce jeu) : %.2f×", zoom).replacingOccurrences(of: ".", with: ",")
        shiftLabel.stringValue = "Position verticale : " + (abs(shift) < 0.01 ? "centrée" : String(format: "%+d %%", Int((shift * 100).rounded())))
    }
    @objc private func pickFilter(_ b: NSButton) {
        Settings.shared.filter = b.tag
        for r in radios { r.state = r.tag == b.tag ? .on : .off }
        changed()
    }
    @objc private func toggleInteger(_ b: NSButton) { Settings.shared.integer = b.state == .on; changed() }
    @objc private func toggleFill(_ b: NSButton) { Settings.shared.fill = b.state == .on; changed() }
    @objc private func framing() {
        zoom = zoomSlider.doubleValue; shift = shiftSlider.doubleValue
        Settings.shared.setFraming(game, zoom, shift)
        labels(); changed()
    }
    private func close() {
        guard let p = panel else { return }
        p.sheetParent?.endSheet(p)
        panel = nil
    }
}
