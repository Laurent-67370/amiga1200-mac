import AppKit

/// Écran d'accueil : Kickstart, disques, machine, préréglages, bouton « Allumer » (même rôle que l'accueil Android).
/// L'émulation tourne dans un second processus (le cœur garde un état global) : l'accueil reste ouvert.
final class HomeDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let s = Settings.shared
    var summary = NSTextField(labelWithString: "")
    var romLabel = NSTextField(labelWithString: "")
    var df0Label = NSTextField(labelWithString: "")
    var df1Label = NSTextField(labelWithString: "")
    var df23Label = NSTextField(labelWithString: "")
    var filterPopup = NSPopUpButton()
    let midiBox = NSStackView()
    var midiOutPopup = NSPopUpButton(), midiInPopup = NSPopUpButton()
    var cdLabel = NSTextField(labelWithString: "")
    let romList = NSStackView()
    var memPopups: [(NSPopUpButton, [Int], () -> Int, (Int) -> Void)] = []
    var accelPopup = NSPopUpButton()
    let resumeButton = NSButton(title: "", target: nil, action: nil)
    let cfgList = NSStackView()
    var hdLabel = NSTextField(wrappingLabelWithString: "")
    var modelPopup = NSPopUpButton()
    var checks: [(NSButton, () -> Bool)] = []
    static let tabNames = ["🎮 Jeux", "💾 Disquettes", "🗄 Disques durs", "💿 CD"]
    let libTabs = NSSegmentedControl(labels: HomeDelegate.tabNames, trackingMode: .selectOne, target: nil, action: nil)
    let libList = NSStackView()
    var libKind = Library.whd

    func applicationDidFinishLaunching(_ n: Notification) {
        Paths.installResources()
        buildMenu()
        let col = NSStackView()
        col.orientation = .vertical; col.alignment = .leading; col.spacing = 10
        col.edgeInsets = NSEdgeInsets(top: 18, left: 22, bottom: 18, right: 22)
        column = col; target = col

        let title = NSTextField(labelWithString: "Amiga 1200")
        title.font = .boldSystemFont(ofSize: 26); title.textColor = .systemOrange
        add(row([title,
            button("✨ Assistant") { [self] in wizard() },
            button("? Aide") { [self] in help() },
            button("🌐 Web") { [self] in web() }]))
        summary.textColor = .secondaryLabelColor
        add(summary)
        let power = NSButton(title: "▶  Allumer l'Amiga", target: self, action: #selector(powerOn))
        power.bezelStyle = .rounded; power.controlSize = .large; power.keyEquivalent = "\r"
        power.font = .boldSystemFont(ofSize: 16)
        power.bezelColor = .systemOrange
        // Reprendre où l'on en était : la machine de l'accueil (mêmes disques) ou le jeu lancé directement
        resumeButton.bezelStyle = .rounded; resumeButton.controlSize = .large
        resumeButton.target = self; resumeButton.action = #selector(resumeGame)
        add(row([power, resumeButton]))

        card("⚡ Préréglages")
        add(row([
            button("AGS / Workbench") { [self] in s.model = "A1200"; s.jit = true; s.rtg = true; refresh() },
            button("A1200 d'origine") { [self] in s.model = "A1200"; s.jit = false; s.rtg = false; stockMemory(); refresh() },
            button("Amiga 500") { [self] in s.model = "A500"; s.jit = false; s.rtg = false; stockMemory(); refresh() },
            button("CD32") { [self] in s.model = "CD32"; refresh() },
        ]))

        card("📚 Bibliothèque")
        libTabs.target = self; libTabs.action = #selector(libTab)
        add(libTabs)
        libList.orientation = .vertical; libList.alignment = .leading; libList.spacing = 4
        add(libList)
        add(row([button("Ajouter des fichiers…") { [self] in addFiles(pickMany("Jeux WHDLoad (.lha, .zip), disquettes, disques durs (.hdf), CD ou Kickstart", multiple: true)) },
                 button("Scanner un dossier…") { [self] in scanFolder() }]))
        add(note("Glissez aussi vos fichiers sur cette fenêtre depuis le Finder. Un jeu WHDLoad se lance d'un clic ; les .zip sont analysés (disque dur ou jeu WHDLoad extraits, archive abîmée signalée) ; un Kickstart est installé comme ROM de la machine."))

        card("🔑 Kickstart")
        add(romLabel)
        romList.orientation = .vertical; romList.alignment = .leading; romList.spacing = 2
        add(romList)
        add(row([
            button("Ajouter des Kickstart…") { [self] in for p in pickMany("Kickstart (fichiers ROM : 1.3 pour l'A500, 3.1 pour l'A1200, ROM de la CD32, extension du CDTV…)", multiple: true) { installRom(p) } },
            button("AROS / mes Kickstart") { [self] in s.rom = s.rom == "aros" ? "user" : "aros"; refresh() },
        ]))
        add(note("Installez-en plusieurs : chacun sert à la machine qui lui convient, reconnu à son contenu (1.3 pour l'Amiga 500, 3.1 pour l'A1200, 3.1.4 et 3.2 compris). La ROM de la CD32 et l'extension du CDTV s'ajoutent de la même façon."))

        card("💾 Disques")
        add(df0Label)
        add(row([
            button("DF0:…") { [self] in if let p = pick("Disquette DF0: (ADF, DMS, IPF…) ou jeu WHDLoad (.lha)") { Library.add(p); s.df0 = p; profile(); refresh() } },
            button("Éjecter DF0:") { [self] in s.df0 = ""; refresh() },
            button("DF1:…") { [self] in if let p = pick("Disquette DF1:") { Library.add(p); s.df1 = p; refresh() } },
            button("Éjecter DF1:") { [self] in s.df1 = ""; refresh() },
        ]))
        add(df1Label)
        add(row([
            button("DF2:…") { [self] in if let p = pick("Disquette DF2:") { Library.add(p); s.df2 = p; refresh() } },
            button("DF3:…") { [self] in if let p = pick("Disquette DF3:") { Library.add(p); s.df3 = p; refresh() } },
            button("Éjecter DF2: et DF3:") { [self] in s.df2 = ""; s.df3 = ""; refresh() },
            button("Disquette vierge…") { [self] in blankDisk() },
        ]))
        add(df23Label)
        add(row([cdLabel, button("Choisir un CD…") { [self] in if let p = pick("CD de la CD32 ou du CDTV (.iso, .chd, .cue)") { Library.add(p); s.cd = p; refresh() } }]))
        add(hdLabel)
        add(row([
            button("Ajouter des disques durs…") { [self] in addHds() },
            button("Retirer les disques durs") { [self] in s.hds = []; refresh() },
        ]))
        add(note("Un jeu WHDLoad (.lha) mis dans DF0: se lance seul. Pour AGS, ajoutez tous ses .hdf d'un coup (Workbench.hdf passe en premier)."))

        card("⚙️ Machine")
        modelPopup.addItems(withTitles: ["A500", "A600", "A1200", "A3000", "A4000", "CD32", "CDTV"])
        modelPopup.target = self; modelPopup.action = #selector(modelChanged)
        add(modelPopup)
        add(check("JIT 68040 : beaucoup plus rapide (A1200, A3000, A4000)", { [self] in s.jit }) { [self] in s.jit = $0 })
        add(check("Carte graphique RTG : haute résolution d'AGS et du Workbench", { [self] in s.rtg }) { [self] in s.rtg = $0 })
        add(check("Volume SHARED: (Documents/Amiga1200/SHARED)", { [self] in s.shared }) { [self] in s.shared = $0 })
        add(check("NTSC 60 Hz (sinon PAL 50 Hz)", { [self] in s.ntsc }) { [self] in s.ntsc = $0 })
        add(check("Bruit des lecteurs de disquettes", { [self] in s.floppySound }) { [self] in s.floppySound = $0 })
        // Mémoire et processeur
        add(row([NSTextField(labelWithString: "Chip"),
            memPopup(["Celle du modèle", "512 Ko", "1 Mo", "2 Mo"], [0, 1, 2, 4], { [self] in s.chip }) { [self] in s.chip = $0 },
            NSTextField(labelWithString: "Slow"),
            memPopup(["Celle du modèle", "Aucune", "512 Ko", "1 Mo"], [-1, 0, 2, 4], { [self] in s.slow }) { [self] in s.slow = $0 },
            NSTextField(labelWithString: "Fast"),
            memPopup(["Aucune", "2 Mo", "4 Mo", "8 Mo"], [0, 2, 4, 8], { [self] in s.fast }) { [self] in s.fast = $0 }]))
        accelPopup.addItems(withTitles: ["Processeur du modèle", "Carte 68030 + FPU 68882", "Carte 68040"])
        accelPopup.target = self; accelPopup.action = #selector(accelChanged)
        add(row([NSTextField(labelWithString: "Sans JIT (A1200, A3000, A4000) :"), accelPopup]))
        add(note("Un jeu qui affiche « Error code 103 » manque de mémoire ; certains vieux jeux A500 ne marchent qu'avec 512 Ko de Chip et sans Slow. Le JIT a déjà 64 Mo de Fast et un 68040."))

        card("🖥 Image")
        filterPopup.addItems(withTitles: ["Lisse", "Nette (pixels francs)", "Écran cathodique (lignes de balayage)"])
        filterPopup.target = self; filterPopup.action = #selector(filterChanged)
        add(row([NSTextField(labelWithString: "Filtre :"), filterPopup]))
        add(check("Pixels réguliers : agrandissement en multiple entier (bandes noires autour)", { [self] in s.integer }) { [self] in s.integer = $0 })
        add(check("Image sur toute la fenêtre (sinon en 4:3)", { [self] in s.fill }) { [self] in s.fill = $0 })
        add(note("Pendant la partie, menu Amiga › Image › Image et cadrage de ce jeu (⌘J) : zoom et position verticale, retenus pour chaque jeu."))

        card("🎹 MIDI")
        add(check("MIDI sur le port série de l'Amiga", { [self] in s.midi }) { [self] in s.midi = $0 })
        midiBox.orientation = .vertical; midiBox.alignment = .leading; midiBox.spacing = 6
        midiOutPopup.target = self; midiOutPopup.action = #selector(midiChanged)
        midiInPopup.target = self; midiInPopup.action = #selector(midiChanged)
        midiBox.addArrangedSubview(row([NSTextField(labelWithString: "Sortie :"), midiOutPopup]))
        midiBox.addArrangedSubview(row([NSTextField(labelWithString: "Entrée :"), midiInPopup]))
        add(midiBox)
        add(note("L'Amiga joue sur un synthétiseur USB, Bluetooth ou réseau, ou sur une application de synthé (GarageBand ne reçoit pas le MIDI : prenez par exemple SimpleSynth ou un instrument virtuel) ; un clavier MIDI peut jouer sur l'Amiga (Bars & Pipes, Music-X, OctaMED…)."))

        card("🗂 Configurations")
        cfgList.orientation = .vertical; cfgList.alignment = .leading; cfgList.spacing = 2
        add(cfgList)
        add(row([
            button("Enregistrer…") { [self] in saveConfig() },
            button("Exporter .uae…") { [self] in exportUae() },
            button("Importer .uae…") { [self] in if let p = pick("Configuration WinUAE ou Amiberry (.uae)") { alert("Import", ConfigsIO.import(s, from: URL(fileURLWithPath: p))); refresh() } },
        ]))
        add(note("Une configuration garde la machine, la mémoire et ses disques. L'export .uae se relit dans WinUAE, Amiberry et les versions web et Android. La machine choisie est aussi retenue pour chaque disque de démarrage."))

        card("📦 Changer de Mac")
        add(row([
            button("Tout exporter…") { [self] in exportBackup() },
            button("Importer…") { [self] in importBackup() },
        ]))
        add(note("Un seul fichier .zip : réglages, Bibliothèque, configurations, Kickstart, sauvegardes d'état, sauvegardes des jeux (WHDLoad, SHARED:), disques extraits des archives et captures. Les jeux rangés ailleurs n'y sont pas : sur l'autre Mac, ajoutez-les à la Bibliothèque. Ce fichier contient vos Kickstart : ne le partagez pas."))
        target = col
        add(note("Pendant le jeu : cliquez dans la fenêtre pour capturer la souris, ⌥⌘ ou F12 pour la libérer. ⌘ = touches Amiga. Menu Amiga : disquettes, sauvegarde rapide (⌘S / ⌘L), image, touches de la manette, quitter le jeu (⌘.), plein écran, réinitialisation. « ? Aide » en haut pour le détail."))

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = col
        col.translatesAutoresizingMaskIntoConstraints = false
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Amiga 1200"
        // Fichiers glissés depuis le Finder : Bibliothèque ou Kickstart
        let drop = DropView(frame: window.contentView?.bounds ?? .zero)
        drop.onDrop = { [self] paths in addFiles(paths) }
        scroll.frame = drop.bounds
        scroll.autoresizingMask = [.width, .height]
        drop.addSubview(scroll)
        window.contentView = drop
        NSLayoutConstraint.activate([
            col.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            col.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            col.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
        ])
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refresh()
        // Premier lancement : l'assistant
        if !UserDefaults.standard.bool(forKey: "aideVue") {
            UserDefaults.standard.set(true, forKey: "aideVue")
            DispatchQueue.main.async { [self] in wizard() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
    /// Retour à l'accueil après une partie : la reprise et les images sont peut-être nouvelles
    func applicationDidBecomeActive(_ n: Notification) { if window != nil { refresh(); checkCrash() } }
    /// Émulation arrêtée brutalement : rapport proposé
    func checkCrash() { CrashReport.check { report, date in CrashReport.present(report, date) } }

    func buildMenu() {
        let bar = NSMenu()
        let appItem = NSMenuItem(); bar.addItem(appItem)
        let app = NSMenu()
        app.addItem(withTitle: "Quitter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app
        let edit = NSMenuItem(); bar.addItem(edit)
        let e = NSMenu(title: "Édition")
        e.addItem(withTitle: "Copier", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        e.addItem(withTitle: "Coller", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.submenu = e
        NSApp.mainMenu = bar
    }

    func refresh() {
        let big = Settings.bigBox(s.model), console = Settings.cdConsole(s.model)
        var parts = [console ? s.model : "Amiga \(s.model.dropFirst())"]
        if big { parts.append(s.jit ? "68040 JIT" : s.accel == "030" ? "68030" : s.accel == "040" ? "68040" : s.model == "A1200" ? "68020" : "68030") }
        if big && s.rtg { parts.append("RTG") }
        let kick = s.kick(s.model)
        if s.model == "CD32" { parts.append(Kickstarts.cd32Rom ? "ROM CD32" : "ROM CD32 manquante") }
        else if s.model == "CDTV" { parts.append(cdtvReady ? "Kickstart + extension CDTV" : "ROM du CDTV manquante") }
        else { parts.append(kick.map { $0.label.components(separatedBy: " (").first ?? $0.label } ?? "AROS") }
        if !console {
            let mem = [[1: "512 Ko Chip", 2: "1 Mo Chip", 4: "2 Mo Chip"][s.chip], s.fast > 0 && !(s.jit && big) ? "\(s.fast) Mo Fast" : nil].compactMap { $0 }
            if !mem.isEmpty { parts.append(mem.joined(separator: " + ")) }
            if !s.hds.isEmpty { parts.append("\(s.hds.count) disque\(s.hds.count > 1 ? "s" : "") dur\(s.hds.count > 1 ? "s" : "")") }
            if !s.df0.isEmpty { parts.append((Settings.isWhd(s.df0) ? "WHDLoad : " : "DF0: ") + (s.df0 as NSString).lastPathComponent) }
        } else { parts.append(s.cd.isEmpty ? "sans CD" : "CD : " + (s.cd as NSString).lastPathComponent) }
        summary.stringValue = parts.joined(separator: " · ")
        let roms = Kickstarts.list()
        let name = s.model == "A500" ? "l'Amiga 500" : "l'\(s.model)"
        romLabel.stringValue = s.model == "CD32" ? (Kickstarts.cd32Rom ? "CD32 : ✓ ROM de la console" : "La CD32 a besoin de sa ROM (kick40060.CD32 + extension, ou ROM complète de 1 Mo).")
            : s.model == "CDTV" ? (cdtvReady ? "CDTV : ✓ Kickstart et extension" : "Le CDTV a besoin d'un Kickstart 1.3 et de son extension (ROM de 256 Ko).")
            : kick != nil ? "Pour \(name) : \(kick!.label)"
            : s.rom == "aros" && !roms.isEmpty ? "AROS (ROM libre) choisi à la place de vos Kickstart."
            : !roms.isEmpty ? "⚠ Aucun de vos Kickstart ne convient à \(name) : AROS démarre à sa place."
            : "AROS, ROM libre fournie. Pour les jeux, WHDLoad et AGS, ajoutez vos Kickstart : 3.1 pour l'A1200, 1.3 pour l'Amiga 500."
        romList.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for r in roms {
            let l = NSTextField(labelWithString: (r.path == kick?.path ? "✓ " : "• ") + r.label)
            l.translatesAutoresizingMaskIntoConstraints = false
            l.widthAnchor.constraint(equalToConstant: 420).isActive = true
            romList.addArrangedSubview(row([l, ClosureButton("✕") { [self] in Kickstarts.remove(r); refresh() }]))
        }
        if Kickstarts.cd32Rom { romList.addArrangedSubview(NSTextField(labelWithString: "• ROM de la CD32" + (FileManager.default.fileExists(atPath: Paths.sys.appendingPathComponent("cd32ext.rom").path) ? " et son extension" : ""))) }
        cdLabel.stringValue = "CD : " + (s.cd.isEmpty ? "aucun" : (s.cd as NSString).lastPathComponent)
        for (p, values, get, _) in memPopups { p.selectItem(at: values.firstIndex(of: get()) ?? 0) }
        accelPopup.selectItem(at: ["none", "030", "040"].firstIndex(of: s.accel) ?? 0)
        let game = s.resumeGame.components(separatedBy: "\n")
        let rf = Settings.resumeFile
        let date = (try? FileManager.default.attributesOfItem(atPath: rf.path)[.modificationDate] as? Date) ?? nil
        let canResume = date != nil && (game.count == 3 || s.resumeSig == s.signature())
        resumeButton.isHidden = !canResume
        if let date, canResume {
            let fmt = DateFormatter(); fmt.locale = Locale(identifier: "fr_FR"); fmt.dateFormat = "dd/MM HH:mm"
            resumeButton.title = "⏯  Reprendre " + (game.count == 3 ? (game[2] as NSString).deletingPathExtension + " " : "où j'en étais ") + "(\(fmt.string(from: date)))"
        }
        cfgList.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let cfgs = s.configs
        if cfgs.isEmpty { cfgList.addArrangedSubview(note("Aucune configuration enregistrée.")) }
        for name in cfgs.keys.sorted() {
            let l = NSTextField(labelWithString: name)
            l.translatesAutoresizingMaskIntoConstraints = false
            l.widthAnchor.constraint(equalToConstant: 300).isActive = true
            cfgList.addArrangedSubview(row([l,
                ClosureButton("Charger") { [self] in if let c = s.configs[name] { s.restore(c); refresh() } },
                ClosureButton("✕") { [self] in var c = s.configs; c[name] = nil; s.configs = c; refresh() }]))
        }
        df0Label.stringValue = "DF0: " + (s.df0.isEmpty ? "vide" : (s.df0 as NSString).lastPathComponent)
        df1Label.stringValue = "DF1: " + (s.df1.isEmpty ? "vide" : (s.df1 as NSString).lastPathComponent)
        df23Label.isHidden = s.df2.isEmpty && s.df3.isEmpty
        df23Label.stringValue = "DF2: " + (s.df2.isEmpty ? "vide" : (s.df2 as NSString).lastPathComponent) +
            "   DF3: " + (s.df3.isEmpty ? "vide" : (s.df3 as NSString).lastPathComponent)
        filterPopup.selectItem(at: s.filter)
        midiBox.isHidden = !s.midi
        if s.midi {
            func fill(_ p: NSPopUpButton, _ first: String, _ names: [String], _ cur: String) {
                p.removeAllItems(); p.addItem(withTitle: first); p.addItems(withTitles: names)
                if !cur.isEmpty && !names.contains(cur) { p.addItem(withTitle: cur + " (absent)") }
                p.selectItem(at: cur.isEmpty ? 0 : (names.firstIndex(of: cur).map { $0 + 1 } ?? names.count + 1))
            }
            fill(midiOutPopup, "Premier appareil trouvé", MidiLink.names(output: true), s.midiOut)
            fill(midiInPopup, "Aucune", MidiLink.names(output: false), s.midiIn)
        }
        hdLabel.stringValue = s.hds.isEmpty ? "Disques durs : aucun" :
            "Disques durs :\n" + s.hds.enumerated().map { "DH\($0.offset): \(($0.element as NSString).lastPathComponent)" }.joined(separator: "\n")
        modelPopup.selectItem(withTitle: s.model)
        refreshLibrary()
        for (b, get) in checks { b.state = get() ? .on : .off }
    }

    // ---------- éléments ----------
    /// Colonne de l'accueil, et carte en cours de remplissage
    private var column: NSStackView!
    private var target: NSStackView!
    func add(_ v: NSView) { target.addArrangedSubview(v) }
    /// Nouvelle carte (titre, puis ce qu'on y ajoute), aussi large que la colonne
    func card(_ title: String) {
        let inner = NSStackView()
        inner.orientation = .vertical; inner.alignment = .leading; inner.spacing = 8
        inner.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 14, right: 14)
        inner.addArrangedSubview(section(title))
        let box = NSBox()
        box.boxType = .custom
        box.cornerRadius = 12
        box.borderColor = .separatorColor
        box.fillColor = .controlBackgroundColor
        box.contentViewMargins = .zero
        box.contentView = inner
        column.addArrangedSubview(box)
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalTo: column.widthAnchor, constant: -44).isActive = true
        target = inner
    }
    private var actions: [() -> Void] = []
    func button(_ t: String, _ f: @escaping () -> Void) -> NSButton {
        actions.append(f)
        let b = NSButton(title: t, target: self, action: #selector(run(_:)))
        b.tag = actions.count - 1
        b.bezelStyle = .rounded
        return b
    }
    @objc func run(_ b: NSButton) { actions[b.tag]() }
    func check(_ t: String, _ get: @escaping () -> Bool, _ set: @escaping (Bool) -> Void) -> NSButton {
        actions.append({})
        let b = NSButton(checkboxWithTitle: t, target: self, action: #selector(toggled(_:)))
        b.tag = actions.count - 1
        setters[b.tag] = set
        checks.append((b, get))
        return b
    }
    private var setters: [Int: (Bool) -> Void] = [:]
    @objc func toggled(_ b: NSButton) { setters[b.tag]?(b.state == .on); refresh() }
    func row(_ v: [NSView]) -> NSStackView { let r = NSStackView(views: v); r.orientation = .horizontal; r.spacing = 8; return r }
    func section(_ t: String) -> NSTextField {
        let l = NSTextField(labelWithString: t); l.font = .boldSystemFont(ofSize: 15); return l
    }
    func note(_ t: String) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: t)
        l.textColor = .secondaryLabelColor; l.font = .systemFont(ofSize: 11)
        l.preferredMaxLayoutWidth = 570
        return l
    }

    func memPopup(_ titles: [String], _ values: [Int], _ get: @escaping () -> Int, _ set: @escaping (Int) -> Void) -> NSPopUpButton {
        let p = NSPopUpButton()
        p.addItems(withTitles: titles)
        p.tag = memPopups.count
        p.target = self; p.action = #selector(memChanged(_:))
        memPopups.append((p, values, get, set))
        return p
    }
    @objc func memChanged(_ p: NSPopUpButton) { let m = memPopups[p.tag]; m.3(m.1[max(p.indexOfSelectedItem, 0)]); refresh() }
    @objc func filterChanged() { s.filter = max(filterPopup.indexOfSelectedItem, 0) }
    @objc func midiChanged() {
        func value(_ p: NSPopUpButton) -> String {
            p.indexOfSelectedItem <= 0 ? "" : (p.titleOfSelectedItem ?? "").replacingOccurrences(of: " (absent)", with: "")
        }
        s.midiOut = value(midiOutPopup); s.midiIn = value(midiInPopup)
    }
    @objc func accelChanged() { s.accel = ["none", "030", "040"][max(accelPopup.indexOfSelectedItem, 0)]; refresh() }
    /// Préréglage « d'origine » : mémoire et processeur du modèle
    func stockMemory() { s.chip = 0; s.slow = -1; s.fast = 0; s.accel = "none" }
    var cdtvReady: Bool { Kickstarts.cdtvExt() != nil && Kickstarts.best("CDTV") != nil }

    // ---------- Bibliothèque ----------
    static let tabKinds = [Library.whd, Library.floppy, Library.hdf, Library.cd]
    @objc func libTab() { libKind = HomeDelegate.tabKinds[max(libTabs.selectedSegment, 0)]; refreshLibrary() }

    func refreshLibrary() {
        let kinds = HomeDelegate.tabKinds
        let items = Library.all()
        func inTab(_ it: LibItem, _ k: String) -> Bool { it.kind == k || (k == Library.whd && it.kind == Library.whdhdf) }
        for (i, k) in kinds.enumerated() {
            let n = items.filter { inTab($0, k) }.count
            libTabs.setLabel(HomeDelegate.tabNames[i] + (n > 0 ? " (\(n))" : ""), forSegment: i)
        }
        libTabs.selectedSegment = kinds.firstIndex(of: libKind) ?? 0
        libList.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let shown = items.filter { inTab($0, libKind) }
        if shown.isEmpty {
            libList.addArrangedSubview(note(libKind == Library.whd ? "Aucun jeu. Ajoutez des archives WHDLoad (.lha, .zip) ou des jeux WHDLoad sur .hdf : un clic les lance."
                : libKind == Library.floppy ? "Aucune disquette (ADF, DMS, IPF…)."
                : libKind == Library.cd ? "Aucun CD de CD32 ou de CDTV (.iso, .chd, .cue)." : "Aucun disque dur (.hdf)."))
            return
        }
        for it in shown {
            var views: [NSView] = []
            let img = NSImageView()
            img.imageScaling = .scaleProportionallyUpOrDown
            img.image = NSImage(contentsOf: Captures.of(it.name))
            img.translatesAutoresizingMaskIntoConstraints = false
            img.widthAnchor.constraint(equalToConstant: 64).isActive = true
            img.heightAnchor.constraint(equalToConstant: 48).isActive = true
            views.append(img)
            let label = NSTextField(labelWithString: it.title + (it.exists ? "" : "  (introuvable)"))
            label.lineBreakMode = .byTruncatingTail
            label.textColor = it.exists ? .labelColor : .tertiaryLabelColor
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(equalToConstant: 300).isActive = true
            views.append(label)
            switch it.kind {
            case Library.whd:
                views.append(ClosureButton("▶ Jouer") { [self] in playWhd(it) })
            case Library.whdhdf:
                views.append(ClosureButton("▶ Jouer") { [self] in playWhdHdf(it) })
            case Library.cd:
                if Kickstarts.cdtvExt() != nil { views.append(ClosureButton("▶ CDTV") { [self] in playCd(it, "CDTV") }) }
                views.append(ClosureButton("▶ CD32") { [self] in playCd(it, "CD32") })
            case Library.floppy:
                views.append(ClosureButton("▶ Jouer") { [self] in Library.touch(it.path); s.df0 = it.path; profile(); refresh(); powerOn() })
                views.append(ClosureButton("DF0:") { [self] in Library.touch(it.path); s.df0 = it.path; profile(); refresh() })
            default:
                let on = s.hds.contains(it.path)
                views.append(ClosureButton(on ? "✓ Branché" : "+ Brancher") { [self] in
                    if on { s.hds = s.hds.filter { $0 != it.path } }
                    else if s.hds.count < 8 { Library.touch(it.path); s.hds = s.hds + [it.path]; profile() }
                    refresh()
                })
            }
            views.append(ClosureButton("✕") { [self] in Library.remove(it.path); refreshLibrary() })
            libList.addArrangedSubview(row(views))
        }
    }

    /// Fichiers choisis ou glissés : un Kickstart est installé, le reste rangé dans la Bibliothèque
    func addFiles(_ paths: [String]) {
        var added = 0, last: String?
        var zips: [String] = [], hdfs: [String] = []
        for p in paths {
            if Library.kind(p) == Library.rom { installRom(p); continue }
            // Archive .zip : son contenu décide (disque dur, jeu WHDLoad ou disquette)
            if (p as NSString).pathExtension.lowercased() == "zip" { zips.append(p); added += 1; continue }
            if Library.add(p) { added += 1; last = Library.kind(p); if last == Library.hdf { hdfs.append(p) } }
        }
        if let k = last { libKind = k }
        if paths.count > 0 && added == 0 && !paths.contains(where: { Library.kind($0) == Library.rom }) {
            alert("Fichiers non reconnus", "La Bibliothèque accepte les jeux WHDLoad (.lha, .zip), les disquettes (ADF, DMS, IPF…), les disques durs (.hdf) et les CD.")
        }
        refresh()
        if zips.isEmpty && hdfs.isEmpty { return }
        // Analyse à part (les archives et les disques peuvent être gros)
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let results = zips.map { ($0, ZipImport.inspect($0)) }
            let games = hdfs.filter { ZipImport.bootsWhdload($0) }
            DispatchQueue.main.async { [self] in
                var notes: [String] = []
                for g in games { Library.add(g, kind: Library.whdhdf); notes.append("\((g as NSString).lastPathComponent) : jeu WHDLoad sur disque dur, rangé dans Jeux (▶ Jouer)"); libKind = Library.whd }
                for (z, r) in results {
                    let n = (z as NSString).lastPathComponent
                    for f in r.found {
                        Library.add(f.path, kind: f.kind)
                        notes.append((f.path as NSString).lastPathComponent + (f.kind == Library.whdhdf ? " : jeu WHDLoad sur disque dur, rangé dans Jeux (▶ Jouer)"
                            : f.kind == Library.whd ? " : jeu WHDLoad, rangé dans Jeux" : " : disque dur, rangé dans Disques durs"))
                        libKind = f.kind == Library.hdf ? Library.hdf : Library.whd
                    }
                    if r.whdArchive { Library.add(z, kind: Library.whd); notes.append("\(n) : jeu WHDLoad, rangé dans Jeux (▶ Jouer)"); libKind = Library.whd }
                    if let p = r.problem { notes.append(p) }
                    if r.found.isEmpty && r.problem == nil && !r.whdArchive { Library.add(z, kind: Library.floppy); libKind = Library.floppy }
                }
                refresh()
                if !notes.isEmpty { alert("Fichiers ajoutés", notes.joined(separator: "\n\n")) }
            }
        }
    }

    /// Jeu installé sur un .hdf qui démarre WHDLoad tout seul : un A1200 avec Kickstart 3.x et 8 Mo de Fast, ce seul disque
    func playWhdHdf(_ it: LibItem) {
        guard Kickstarts.hasForWhd() else {
            alert("Kickstart nécessaire", "WHDLoad a besoin d'un vrai Kickstart (3.1 de l'A1200 de préférence) : AROS ne lui suffit pas.")
            return
        }
        Library.touch(it.path)
        launch(Config.write(s, whdHdf: it.path).path, game: it.name, hdf: it.path)
    }

    /// CD de la CD32 ou du CDTV : la console démarre dessus (il lui faut ses ROM)
    func playCd(_ it: LibItem, _ console: String) {
        if console == "CD32" && !Kickstarts.cd32Rom {
            alert("ROM de la CD32 nécessaire", "La CD32 démarre sur sa propre ROM : ajoutez kick40060.CD32 (puis son extension), ou une ROM complète de 1 Mo, avec « Ajouter des Kickstart… »."); return
        }
        if console == "CDTV" && !cdtvReady {
            alert("ROM du CDTV nécessaires", "Le CDTV démarre sur un Kickstart 1.3 et sur son extension (ROM de 256 Ko) : ajoutez-les avec « Ajouter des Kickstart… »."); return
        }
        Library.touch(it.path)
        s.cd = it.path; s.model = console
        refresh()
        powerOn()
    }

    func playWhd(_ it: LibItem) {
        guard Kickstarts.hasForWhd() else {
            alert("Kickstart nécessaire", "WHDLoad a besoin d'un vrai Kickstart (3.1 de l'A1200 de préférence) : AROS ne lui suffit pas.")
            return
        }
        Library.touch(it.path)
        launch(it.path)
    }

    @objc func modelChanged() { s.model = modelPopup.titleOfSelectedItem ?? "A1200"; refresh() }

    func pick(_ message: String, multiple: Bool = false) -> String? { pickMany(message, multiple: false).first }
    func pickMany(_ message: String, multiple: Bool) -> [String] {
        let p = NSOpenPanel()
        p.message = message
        p.allowsMultipleSelection = multiple
        p.canChooseDirectories = false
        return p.runModal() == .OK ? p.urls.map(\.path) : []
    }

    /// Kickstart ajouté aux autres (reconnu à son contenu), choisi ensuite selon la machine
    func installRom(_ p: String) {
        let (rom, why) = Kickstarts.install(p)
        if rom == nil { alert("Kickstart refusé", "\((p as NSString).lastPathComponent) : \(why ?? "")") }
        else { s.rom = "user" }
        refresh()
    }

    func addHds() {
        var list = s.hds
        for p in pickMany("Disques durs .hdf (8 au plus)", multiple: true) where !list.contains(p) && list.count < 8 { list.append(p) }
        // Le Workbench d'AGS démarre : placé en premier
        list.sort { a, b in ((a as NSString).lastPathComponent.lowercased() == "workbench.hdf" ? 0 : 1) < ((b as NSString).lastPathComponent.lowercased() == "workbench.hdf" ? 0 : 1) }
        s.hds = list
        refresh()
    }

    /// Disquette formatée (880 Ko) pour les sauvegardes des jeux : rangée dans la Bibliothèque et mise dans DF1:
    func blankDisk() {
        guard let u = savePanel("Sauvegardes.adf", "adf") else { return }
        guard (try? BlankDisk.adf(u.deletingPathExtension().lastPathComponent).write(to: u)) != nil else { alert("Disquette vierge", "Création impossible"); return }
        Library.add(u.path); s.df1 = u.path
        libKind = Library.floppy
        refresh()
    }

    func alert(_ t: String, _ msg: String) {
        let a = NSAlert(); a.messageText = t; a.informativeText = msg; a.runModal()
    }

    /// Machine retenue pour ce disque de démarrage (JIT ou non, mémoire…) : reprise d'elle-même
    func profile() { s.applyProfile() }

    func saveConfig() {
        let a = NSAlert(); a.messageText = "Enregistrer la configuration"
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        f.stringValue = (s.bootKey() as NSString).deletingPathExtension
        a.accessoryView = f
        a.addButton(withTitle: "Enregistrer"); a.addButton(withTitle: "Annuler")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let n = f.stringValue.trimmingCharacters(in: .whitespaces)
        if n.isEmpty { return }
        var c = s.configs; c[n] = s.snapshot(); s.configs = c
        refresh()
    }

    func savePanel(_ name: String, _ ext: String) -> URL? {
        let p = NSSavePanel()
        p.nameFieldStringValue = name
        p.allowedFileTypes = [ext]
        return p.runModal() == .OK ? p.url : nil
    }
    func exportUae() {
        guard let u = savePanel(((s.bootKey().isEmpty ? "amiga" : s.bootKey()) as NSString).deletingPathExtension + ".uae", "uae") else { return }
        alert("Export", ConfigsIO.export(s, to: u) ? "Configuration exportée : \(u.lastPathComponent)" : "Export impossible")
    }
    func exportBackup() {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        guard let u = savePanel("amiga1200-sauvegarde-\(fmt.string(from: Date())).zip", "zip") else { return }
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let msg = Backup.export(to: u)
            DispatchQueue.main.async { [self] in alert("Changer de Mac", msg) }
        }
    }
    func importBackup() {
        guard let p = pick("Sauvegarde d'Amiga 1200 (.zip)") else { return }
        let a = NSAlert(); a.messageText = "Importer la sauvegarde ?"
        a.informativeText = "Les réglages, la Bibliothèque et les configurations sont remplacés par ceux de la sauvegarde ; ses Kickstart, sauvegardes d'état et captures s'ajoutent. Éteignez l'Amiga avant."
        a.addButton(withTitle: "Importer"); a.addButton(withTitle: "Annuler")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let msg = Backup.import(from: URL(fileURLWithPath: p))
            DispatchQueue.main.async { [self] in refresh(); alert("Changer de Mac", msg) }
        }
    }

    /// « Reprendre où j'en étais » : la machine de l'accueil, ou le jeu lancé directement (WHDLoad, .hdf)
    @objc func resumeGame() {
        let g = s.resumeGame.components(separatedBy: "\n")
        if g.count == 3 && g[0] == "whd" { launch(g[1], resume: true) }
        else if g.count == 3 && g[0] == "hdf" { launch(Config.write(s, whdHdf: g[1]).path, game: g[2], hdf: g[1], resume: true) }
        else { launch(Config.content(s), resume: true) }
    }

    /// L'émulation dans un nouveau processus de cette application (le cœur ne se rallume pas dans le même)
    @objc func powerOn() {
        if s.model == "CD32" && !Kickstarts.cd32Rom {
            alert("ROM de la CD32 nécessaire", "La CD32 démarre sur sa propre ROM : ajoutez kick40060.CD32 (puis son extension), ou une ROM complète de 1 Mo."); return
        }
        if s.model == "CDTV" && !cdtvReady {
            alert("ROM du CDTV nécessaires", "Le CDTV démarre sur un Kickstart 1.3 et sur son extension (ROM de 256 Ko)."); return
        }
        if Settings.isWhd(s.df0) && !Kickstarts.hasForWhd() {
            alert("Kickstart nécessaire", "WHDLoad a besoin d'un vrai Kickstart (3.1 de l'A1200 de préférence) : AROS ne lui suffit pas.")
            return
        }
        if !s.df0.isEmpty { Library.add(s.df0) }
        for h in s.hds { Library.add(h) }
        launch(Config.content(s))
        refresh()
    }

    /// L'émulation dans un nouveau processus de cette application
    func launch(_ content: String, game: String? = nil, hdf: String? = nil, resume: Bool = false) {
        let p = Process()
        p.executableURL = Bundle.main.executableURL
        p.arguments = ["--emu", content] + (resume ? ["--resume"] : [])
        // Nom du jeu (sa capture dans la Bibliothèque) quand le contenu est une configuration, et son disque (reprise)
        var env = ProcessInfo.processInfo.environment
        env["AMIGA1200_JEU"] = game
        env["AMIGA1200_HDF"] = hdf
        p.environment = env
        p.terminationHandler = { [weak self] _ in DispatchQueue.main.async { self?.checkCrash() } }
        do { try p.run() } catch { alert("Démarrage impossible", error.localizedDescription) }
    }
}
