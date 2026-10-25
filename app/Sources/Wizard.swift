import AppKit

/// Assistant de premier lancement et aide (comme la version Android) : ce que l'on veut faire, les Kickstart qu'il
/// faut, les fichiers à ranger dans la Bibliothèque, puis le geste qui lance
extension HomeDelegate {
    private func ask(_ title: String, _ msg: String, _ buttons: [String]) -> Int {
        let a = NSAlert(); a.messageText = title; a.informativeText = msg
        for b in buttons { a.addButton(withTitle: b) }
        return a.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
    }

    func wizard() {
        // Étape 1 : ce que l'on veut faire
        let goals = [
            ("whd", "🎮 Des jeux WHDLoad (.lha, .zip), lancés d'un clic"),
            ("floppy", "💾 Des disquettes de jeux ou de démos (.adf, .dms, .ipf)"),
            ("ags", "🗄 AGS ou un Workbench installé (disques .hdf)"),
            ("cd", "💿 Des jeux sur CD (CD32 ou CDTV)"),
            ("aros", "🔍 Découvrir l'Amiga sans rien installer (AROS)"),
        ]
        let a = NSAlert(); a.messageText = "Bienvenue ! Que voulez-vous faire ?"
        a.informativeText = "L'assistant règle la machine et vous guide pas à pas. Il reste disponible avec « ✨ Assistant », en haut de la fenêtre."
        let p = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 420, height: 26))
        p.addItems(withTitles: goals.map(\.1))
        a.accessoryView = p
        a.addButton(withTitle: "Continuer"); a.addButton(withTitle: "Plus tard")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let goal = goals[max(p.indexOfSelectedItem, 0)].0
        if goal == "aros" {
            s.rom = "aros"; s.model = "A1200"; s.jit = true; s.rtg = true; refresh()
            wizardDone(goal); return
        }

        // Étape 2 : les Kickstart qu'il faut pour ce choix
        let have: Bool
        switch goal {
        case "cd": have = Kickstarts.cd32Rom || cdtvReady
        case "floppy": have = Kickstarts.list().contains { !$0.cdtvExt && !$0.models.contains("CD32") }
        default: have = Kickstarts.hasForWhd()
        }
        let need: String
        switch goal {
        case "whd": need = "WHDLoad a besoin de votre Kickstart 3.1 de l'A1200 (ou 3.0, 3.1.4, 3.2) : avec la ROM libre AROS, il ne démarre pas."
        case "ags": need = "AGS et le Workbench ont besoin de votre Kickstart 3.1 de l'A1200 (ou plus récent)."
        case "floppy": need = "Les jeux sur disquette veulent le Kickstart de leur machine : 1.3 pour l'Amiga 500 (la plupart), 3.1 pour les jeux A1200. Choisissez-en plusieurs : chacun servira à la machine qui lui convient."
        default: need = "La CD32 démarre sur sa ROM (kick40060.CD32 et son extension, ou la ROM complète de 1 Mo) ; le CDTV sur un Kickstart 1.3 et son extension."
        }
        let r = ask(have ? "Kickstart : ✓ déjà installés" : "Vos Kickstart",
                    (have ? "Vous pouvez en ajouter d'autres.\n\n" : "") + need +
                    "\n\nLes Kickstart sont les ROM de l'Amiga : ils ne sont pas fournis. On les trouve dans Amiga Forever (Cloanto) ou on les copie de son propre Amiga.",
                    have ? ["Continuer", "En ajouter…", "Annuler"] : ["Choisir mes Kickstart…", "Je n'en ai pas", "Annuler"])
        if r == 2 { return }
        if (have && r == 1) || (!have && r == 0) {
            for f in pickMany("Kickstart (fichiers ROM : 1.3 pour l'A500, 3.1 pour l'A1200, ROM de la CD32, extension du CDTV…)", multiple: true) { installRom(f) }
        }

        // Étape 3 : la machine qui convient, puis les fichiers à ranger dans la Bibliothèque
        if !Kickstarts.list().isEmpty { s.rom = "user" }
        switch goal {
        case "whd": s.model = "A1200"; s.jit = true; s.rtg = true; libKind = Library.whd
        case "ags": s.model = "A1200"; s.jit = true; s.rtg = true; s.shared = true; libKind = Library.hdf
        case "floppy":
            s.model = Kickstarts.best("A500") != nil || Kickstarts.list().isEmpty ? "A500" : "A1200"
            s.jit = false; s.rtg = false; stockMemory(); libKind = Library.floppy
        default: s.model = !Kickstarts.cd32Rom && cdtvReady ? "CDTV" : "CD32"; libKind = Library.cd
        }
        refresh()
        let what: String
        switch goal {
        case "whd": what = "Choisissez vos jeux WHDLoad (.lha, .zip), plusieurs d'un coup si vous voulez. Ils restent où ils sont : l'application les lit sur place."
        case "ags": what = "Choisissez d'un coup tous les fichiers .hdf d'AGS (ou votre disque Workbench). Ils sont lus sur place, même s'ils font plusieurs Go."
        case "floppy": what = "Choisissez vos disquettes, plusieurs d'un coup si vous voulez. La première ira dans le lecteur DF0:."
        default: what = "Choisissez vos CD (.iso, .chd ou .cue)."
        }
        if ask("Vos fichiers", what + "\n\nVous pourrez aussi glisser des fichiers sur la fenêtre depuis le Finder.", ["Choisir…", "Plus tard"]) == 0 {
            if goal == "ags" { addHds() } else { addFiles(pickMany(what, multiple: true)) }
        }
        wizardDone(goal)
    }

    /// Étape 4 : ce qu'il reste à faire
    private func wizardDone(_ goal: String) {
        let items = Library.all()
        if goal == "floppy" && s.df0.isEmpty, let f = items.first(where: { $0.kind == Library.floppy }) { s.df0 = f.path }
        if goal == "cd" && s.cd.isEmpty, let c = items.first(where: { $0.kind == Library.cd }) { s.cd = c.path }
        refresh()
        let name = { (p: String) in (p as NSString).lastPathComponent }
        let msg: String, canPower: Bool
        switch goal {
        case "whd":
            msg = items.contains { $0.kind == Library.whd || $0.kind == Library.whdhdf }
                ? "Cliquez sur « ▶ Jouer » à côté d'un jeu, dans la Bibliothèque (onglet Jeux) : il démarre directement."
                : "Ajoutez vos jeux .lha ou .zip avec « Ajouter des fichiers… » (Bibliothèque), puis cliquez sur « ▶ Jouer »."
            canPower = false
        case "floppy":
            msg = !s.df0.isEmpty ? "\(name(s.df0)) est dans DF0:. Allumez ! Pour changer de disquette, cliquez sur « DF0: » à côté d'une autre dans la Bibliothèque."
                : "Ajoutez vos disquettes à la Bibliothèque, cliquez sur « DF0: » à côté de l'une d'elles, puis allumez."
            canPower = !s.df0.isEmpty
        case "ags":
            msg = !s.hds.isEmpty ? "Les disques sont branchés : allumez, AGS démarre." : "Ajoutez les disques .hdf avec « Ajouter des disques durs… », puis allumez."
            canPower = !s.hds.isEmpty
        case "cd":
            msg = !s.cd.isEmpty ? "\(name(s.cd)) est prêt : allumez, ou cliquez sur « ▶ CD32 » / « ▶ CDTV » à côté d'un autre CD de la Bibliothèque."
                : "Ajoutez vos CD à la Bibliothèque, puis cliquez sur « ▶ CD32 » ou « ▶ CDTV »."
            canPower = !s.cd.isEmpty
        default:
            msg = "AROS, la ROM libre, démarre un Workbench à découvrir. Pour les jeux, ajoutez plus tard vos Kickstart (section Kickstart)."
            canPower = true
        }
        let r = ask("C'est prêt", msg + "\n\nPendant le jeu : cliquez dans la fenêtre pour capturer la souris (⌥⌘ ou F12 pour la libérer) ; le menu Amiga donne les disquettes, les sauvegardes d'état, l'image, les touches de la manette et la sortie d'un jeu WHDLoad (⌘.).",
                    canPower ? ["▶ Allumer", "Aide détaillée", "Fermer"] : ["OK", "Aide détaillée"])
        if r == 0 && canPower { powerOn() } else if r == 1 { help() }
    }

    /// La version web, à l'origine du projet : même cœur, rien à installer ; les configurations .uae passent de l'une à l'autre
    static let webURL = "https://laurent-67370.github.io/amiga1200/"
    func web() {
        let a = NSAlert()
        a.messageText = "🌐 La version web"
        a.informativeText = """
            Amiga 1200 est né dans le navigateur : la version web tourne sur le même cœur Amiberry, sans rien installer, sur ordinateur, tablette ou téléphone.

            \(HomeDelegate.webURL)

            Passer de l'une à l'autre : exportez une configuration .uae ici (Configurations › Exporter .uae…), importez-la dans la version web, et inversement. Vos Kickstart et vos disques restent à ajouter de chaque côté.
            """
        a.addButton(withTitle: "Ouvrir la version web")
        a.addButton(withTitle: "Copier le lien")
        a.addButton(withTitle: "Fermer")
        switch a.runModal() {
        case .alertFirstButtonReturn: if let u = URL(string: HomeDelegate.webURL) { NSWorkspace.shared.open(u) }
        case .alertSecondButtonReturn: NSPasteboard.general.clearContents(); NSPasteboard.general.setString(HomeDelegate.webURL, forType: .string)
        default: break
        }
    }

    func help() {
        alert("Bien démarrer", """
            1. Kickstart : ajoutez vos fichiers ROM, plusieurs si vous voulez (3.1 pour l'A1200, 1.3 pour l'Amiga 500) : chacun sert à la machine qui lui convient. Sans eux, la ROM libre AROS démarre, mais WHDLoad, AGS et la plupart des jeux demandent un vrai Kickstart.
            Le plus simple : Bibliothèque › « Scanner un dossier… » (celui d'Amiga Forever, une clé USB, votre dossier Amiga) : Kickstart, jeux WHDLoad, disquettes, disques durs, CD et configurations .uae sont reconnus d'un coup ; un bilan montre ce qui est déjà là et les Kickstart qui manquent.
            2. Jeux et disques : ajoutez vos jeux WHDLoad (.lha, .zip), disquettes, disques durs (.hdf) et CD à la Bibliothèque, ou glissez-les sur la fenêtre. Ils sont lus sur place, sans copie. Un jeu WHDLoad se lance d'un clic (▶ Jouer). Pour AGS, ajoutez tous ses .hdf d'un coup.
            3. Préréglage : « AGS / Workbench » pour AGS et le Workbench, « Amiga 500 » pour les vieux jeux, « CD32 » pour la console. Section Machine : A600, A3000, A4000 et CDTV aussi, mémoire et carte accélératrice.
            4. Allumez.

            Pendant le jeu :
            • souris : un clic dans la fenêtre la capture, ⌥⌘ ou F12 la libère ; ⌘ = touches Amiga tant qu'elle est capturée
            • manettes : la première joue sur le port joystick, la deuxième sur le port souris ; menu Amiga › Touches de la manette pour changer des boutons en touches du clavier (pour ce jeu)
            • ⌘P pause · ⌘S / ⌘L sauvegarde et reprise rapides · ⌘E les 4 emplacements avec leur image
            • ⌘O / ⇧⌘O disquettes DF0: et DF1: · ⌘N disquette vierge (pour les sauvegardes des jeux)
            • ⌘. quitter un jeu WHDLoad (F10 ; * ou Échap dans Touche de sortie)
            • ⌘I filtre de l'image (lisse, net, écran cathodique) · ⌘J image et cadrage de ce jeu (zoom, position) · ⌃⌘F plein écran · ⌘K capture · ⌘T turbo · ⌘R réinitialiser
            • quitter la fenêtre garde l'état : « ⏯ Reprendre » le retrouve à l'accueil

            Si l'émulation s'arrête brutalement, l'accueil prépare un rapport (journal et rapport de macOS) à copier ou à signaler sur GitHub.

            À l'accueil aussi : DF2: et DF3:, Image (filtre, pixels réguliers), MIDI (synthétiseur ou clavier par CoreMIDI), configurations enregistrées et export .uae, et « Changer de Mac » : tout exporter dans un fichier .zip, puis l'importer sur un autre Mac.

            🌐 Web : la version web d'origine, dans le navigateur (\(HomeDelegate.webURL)) ; les configurations .uae passent de l'une à l'autre.
            """)
    }
}
