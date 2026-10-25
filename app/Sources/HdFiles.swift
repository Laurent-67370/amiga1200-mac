import AppKit

/// Ajouter des fichiers sur un disque dur (.hdf) sans passer par l'Amiga, avec native/hdtools.c (comme « Fichiers… »
/// de la version web) : jeux WHDLoad .lha et .zip décompressés, disquettes .adf ouvertes, dossiers copiés tels quels.
enum HdFiles {
    struct Part { let name, volume, fs, reason: String; let free: Int64; let ok: Bool }

    static func partitions(_ hdf: String) -> ([Part], String?) {
        var out = [CChar](repeating: 0, count: 16384)
        let n = hdt_partitions(hdf, &out, Int32(out.count))
        let text = String(cString: out)
        if n < 0 { return ([], text) }
        let parts = text.split(separator: "\n").map { line -> Part in
            var f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            while f.count < 6 { f.append("") }
            return Part(name: f[0], volume: f[1], fs: f[2], reason: f[5], free: Int64(f[3]) ?? 0, ok: f[4] == "1")
        }
        return (parts, nil)
    }

    /// Copie (dst vide : dans dest, décompressé si unpack ; sinon chemins exacts) ; renvoie le compte rendu
    static func copy(_ hdf: String, part: Int, dest: String, src: [String], dst: [String], unpack: Bool) -> String {
        let cs = src.map { UnsafePointer(strdup($0)) }, cd = dst.map { UnsafePointer(strdup($0)) }
        defer { (cs + cd).forEach { free(UnsafeMutablePointer(mutating: $0)) } }
        var rep = [CChar](repeating: 0, count: 65536)
        cs.withUnsafeBufferPointer { sp in
            cd.withUnsafeBufferPointer { dp in
                _ = hdt_copy(hdf, Int32(part), dest, sp.baseAddress, dst.isEmpty ? nil : dp.baseAddress, Int32(src.count),
                             unpack ? 1 : 0, &rep, Int32(rep.count))
            }
        }
        return String(cString: rep)
    }

    /// Préparer pour WHDLoad : WHDLoad dans C:, ses .RTB et vos Kickstart (noms de WHDLoad) dans Devs:Kickstarts
    static func whdSources() -> ([String], [String]) {
        let wb = Paths.resources.appendingPathComponent("whdboot")
        var src = [wb.appendingPathComponent("WHDLoad").path], dst = ["C/WHDLoad"]
        let rtb = wb.appendingPathComponent("save-data/Kickstarts")
        for n in ((try? FileManager.default.contentsOfDirectory(atPath: rtb.path)) ?? []).sorted() where n.lowercased().hasSuffix(".rtb") {
            src.append(rtb.appendingPathComponent(n).path); dst.append("Devs/Kickstarts/" + n)
        }
        for r in Kickstarts.list() { if let n = Config.whdKickNames[r.crc] { src.append(r.path); dst.append("Devs/Kickstarts/" + n) } }
        return (src, dst)
    }

    /// Un dossier entier, dans un dossier à son nom (fichiers cachés exclus)
    static func folderSources(_ root: URL, base: String) -> ([String], [String]) {
        var src: [String] = [], dst: [String] = []
        let top = (base.isEmpty ? "" : base + "/") + root.lastPathComponent
        let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        while let u = e?.nextObject() as? URL {
            guard (try? u.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            src.append(u.path)
            dst.append(top + "/" + String(u.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1)))
        }
        return (src, dst)
    }
}

extension HomeDelegate {
    /// Bouton de la carte Disques : le disque dur branché, ou celui choisi parmi eux, sinon un .hdf à choisir
    func hdAddFilesPick() {
        if s.hds.count == 1 { hdAddFiles(s.hds[0]); return }
        if s.hds.isEmpty {
            if let p = pick("Disque dur (.hdf) sur lequel copier des fichiers") { hdAddFiles(p) }
            return
        }
        let a = NSAlert()
        a.messageText = "Sur quel disque dur ?"
        let popup = NSPopUpButton()
        for (i, h) in s.hds.enumerated() { popup.addItem(withTitle: "DH\(i): \((h as NSString).lastPathComponent)") }
        popup.frame = NSRect(x: 0, y: 0, width: 320, height: 26)
        a.accessoryView = popup
        a.addButton(withTitle: "Continuer"); a.addButton(withTitle: "Annuler")
        if a.runModal() == .alertFirstButtonReturn { hdAddFiles(s.hds[popup.indexOfSelectedItem]) }
    }

    /// Fenêtre « Ajouter sur le disque » : partition, dossier, décompression, puis fichiers, dossier ou WHDLoad
    func hdAddFiles(_ hdf: String, log: String = "") {
        let name = (hdf as NSString).lastPathComponent
        if emuRunning > 0 {
            alert("Ajouter sur « \(name) »", "L'Amiga est allumé : éteignez-le d'abord, le disque ne doit pas servir pendant la copie.")
            return
        }
        let (parts, err) = HdFiles.partitions(hdf)
        if let err { alert("Ajouter sur « \(name) »", "Disque illisible : \(err)"); return }
        let a = NSAlert()
        a.messageText = "Ajouter sur le disque « \(name) »"
        a.informativeText = log.isEmpty ? "Un jeu WHDLoad (.lha) arrive dans son propre dossier, avec son icône. Une disquette .adf est ouverte : ses fichiers vont dans un dossier à son nom. Laissez le dossier vide pour copier à la racine du disque. Un fichier du même nom est remplacé." : log
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        let popup = NSPopUpButton()
        popup.autoenablesItems = false
        for p in parts {
            let free = String(format: "%.1f Mo libres", Double(p.free) / 1048576)
            popup.addItem(withTitle: "\(p.name):" + (p.volume.isEmpty ? "" : " « \(p.volume) »") + " — \(p.fs)" + (p.ok ? " — \(free)" : " : \(p.reason)"))
            popup.lastItem?.isEnabled = p.ok
        }
        if let i = parts.firstIndex(where: { $0.ok }) { popup.selectItem(at: i) }
        let dest = NSTextField(string: hdDest)
        dest.placeholderString = "racine du disque"
        dest.widthAnchor.constraint(equalToConstant: 200).isActive = true
        let unpack = NSButton(checkboxWithTitle: "Décompresser les archives .lha et .zip, ouvrir les disquettes .adf", target: nil, action: nil)
        unpack.state = hdUnpack ? .on : .off
        let hasKick = Kickstarts.list().contains { Config.whdKickNames[$0.crc] != nil }
        let whd = NSTextField(wrappingLabelWithString: hasKick
            ? "« Préparer pour WHDLoad » copie WHDLoad dans C: et, dans Devs:Kickstarts, ses fichiers .RTB et vos Kickstart. Ensuite, un jeu WHDLoad copié sur ce disque se lance d'un double-clic sur son icône, depuis le Workbench."
            : "« Préparer pour WHDLoad » copie WHDLoad dans C: et ses fichiers .RTB dans Devs:Kickstarts. Aucun Kickstart reconnu pour WHDLoad (1.3 A500, 2.04, 3.0 ou 3.1 A1200) : ajoutez-le d'abord pour qu'il soit copié aussi.")
        whd.preferredMaxLayoutWidth = 460; whd.font = .systemFont(ofSize: 11); whd.textColor = .secondaryLabelColor
        stack.addArrangedSubview(popup)
        stack.addArrangedSubview(row([NSTextField(labelWithString: "Dans le dossier"), dest]))
        stack.addArrangedSubview(unpack)
        stack.addArrangedSubview(whd)
        stack.frame = NSRect(x: 0, y: 0, width: 470, height: stack.fittingSize.height)
        a.accessoryView = stack
        a.addButton(withTitle: "Fichiers ou archives…")
        a.addButton(withTitle: "Un dossier…")
        a.addButton(withTitle: "Préparer pour WHDLoad")
        a.addButton(withTitle: "Fermer")
        let canCopy = parts.contains { $0.ok }
        for i in 0..<3 { a.buttons[i].isEnabled = canCopy }
        let r = a.runModal()
        hdDest = dest.stringValue.trimmingCharacters(in: .whitespaces)
        hdUnpack = unpack.state == .on
        let part = popup.indexOfSelectedItem
        var src: [String] = [], dst: [String] = [], doUnpack = false
        switch r {
        case .alertFirstButtonReturn:
            src = pickMany("Fichiers à copier sur le disque dur (.lha, .zip, .adf ou autres)", multiple: true); doUnpack = hdUnpack
        case .alertSecondButtonReturn:
            let p = NSOpenPanel()
            p.message = "Dossier à copier sur le disque dur, avec ses sous-dossiers"
            p.canChooseDirectories = true; p.canChooseFiles = false; p.prompt = "Copier"
            guard p.runModal() == .OK, let u = p.url else { hdAddFiles(hdf); return }
            (src, dst) = HdFiles.folderSources(u, base: hdDest)
            if src.isEmpty { hdAddFiles(hdf, log: "Ce dossier est vide."); return }
        case .alertThirdButtonReturn:
            (src, dst) = HdFiles.whdSources()
        default:
            return
        }
        if src.isEmpty { hdAddFiles(hdf); return }
        let (sheet, _) = hdProgress()
        let d = hdDest
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let rep = HdFiles.copy(hdf, part: part, dest: d, src: src, dst: dst, unpack: doUnpack)
            DispatchQueue.main.async { [self] in
                window.endSheet(sheet.window)
                hdAddFiles(hdf, log: rep)
            }
        }
    }

    private func hdProgress() -> (NSAlert, NSTextField) {
        let a = NSAlert()
        a.messageText = "Copie en cours…"
        let label = NSTextField(wrappingLabelWithString: "Le disque est modifié seulement si toute la copie réussit.")
        label.frame = NSRect(x: 0, y: 0, width: 380, height: 32)
        a.accessoryView = label
        a.addButton(withTitle: "Patientez…").isEnabled = false
        a.beginSheetModal(for: window) { _ in }
        return (a, label)
    }
}
