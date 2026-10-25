import AppKit

/// Scanner un dossier (comme la version web et Android) : le dossier choisi est parcouru avec ses sous-dossiers,
/// chaque fichier reconnu par son contenu (Kickstart par empreinte, ROM chiffrées d'Amiga Forever avec le rom.key du
/// dossier, disquettes, jeux WHDLoad, disques durs, CD, configurations .uae, archives .zip). Un bilan permet de
/// choisir ce qui rejoint la Bibliothèque ; les fichiers restent où ils sont (lus sur place) et les Kickstart sont
/// installés comme ROM de la machine.
enum Scan {
    static let key = "key", zip = "zip", uae = "uae"
    static let maxFiles = 20000
    private static let skip: Set<String> = ["__MACOSX", "$RECYCLE.BIN", "System Volume Information"]
    static let cd32Ext: UInt32 = 0x87746BE2

    final class Item {
        let path: String, rel: String, size: Int
        var name: String { (path as NSString).lastPathComponent }
        var kind: String?
        /// Ce que c'est (Kickstart reconnu, nom de la configuration…)
        var label = ""
        /// Pourquoi il n'est pas proposé (déjà là, en double, pistes absentes…) ; vide : importable
        var why = ""
        var on = true
        /// ROM en clair, prête à installer, et ses usages (a1200, a500, cd32main, cd32ext, cdtvext)
        var rom: Data?
        var tags: Set<String> = []
        init(path: String, rel: String, size: Int) { self.path = path; self.rel = rel; self.size = size }
    }
    final class Stop { var stop = false }

    /// Tous les fichiers du dossier et de ses sous-dossiers (fichiers cachés, paquets et corbeilles ignorés)
    static func walk(_ root: URL, _ stop: Stop, _ progress: (Int) -> Void) -> [Item] {
        var out: [Item] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        let base = root.path.hasSuffix("/") ? root.path : root.path + "/"
        while let u = e.nextObject() as? URL {
            if stop.stop || out.count >= maxFiles { break }
            let v = try? u.resourceValues(forKeys: Set(keys))
            if v?.isDirectory == true {
                if skip.contains(u.lastPathComponent) || e.level > 12 { e.skipDescendants() }
                continue
            }
            let rel = u.path.hasPrefix(base) ? String(u.path.dropFirst(base.count)) : u.lastPathComponent
            out.append(Item(path: u.path, rel: root.lastPathComponent + "/" + rel, size: v?.fileSize ?? 0))
            if out.count % 50 == 0 { progress(out.count) }
        }
        // Les fichiers les moins enfouis d'abord : l'original passe avant ses copies rangées plus loin
        func depth(_ i: Item) -> Int { i.rel.filter { $0 == "/" }.count }
        return out.sorted { depth($0) != depth($1) ? depth($0) < depth($1) : $0.rel < $1.rel }
    }

    /// Archive LhA d'un jeu WHDLoad : le nom d'un .slave figure en clair dans les en-têtes
    private static func hasSlave(_ path: String) -> Bool {
        guard let h = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? h.close() }
        var tail = ""
        while true {
            let d = h.readData(ofLength: 1 << 20)
            if d.isEmpty { return false }
            let t = tail + (String(data: d, encoding: .isoLatin1) ?? "")
            if t.lowercased().contains(".slave") { return true }
            tail = String(t.suffix(16))
        }
    }

    /// Contenu d'un .zip : zip (disque dur ou jeu .lha, à extraire), whd (dossier d'un jeu WHDLoad), floppy, ou nil
    private static func zipKind(_ path: String) -> String? {
        let names = ZipImport.entries(path).map { ($0 as NSString).lastPathComponent.lowercased() }
        if names.contains(where: { ["hdf", "hdz", "lha", "lzh"].contains(($0 as NSString).pathExtension) }) { return zip }
        if names.contains(where: { $0.hasSuffix(".slave") }) { return Library.whd }
        if names.contains(where: { ["adf", "adz", "dms", "ipf"].contains(($0 as NSString).pathExtension) }) { return Library.floppy }
        return nil
    }

    struct RomInfo { let plain: Data?; let label: String; let tags: Set<String>; var aros = false }

    /// Ce qu'est une ROM (déchiffrée avec key si elle vient d'Amiga Forever) ; nil si ce n'en est pas une
    static func romInfo(_ b: Data, _ key: Data?) -> RomInfo? {
        var p = b
        if b.count >= 11 && String(data: b.prefix(11), encoding: .ascii) == "AMIROMTYPE1" {
            guard let k = key, !k.isEmpty else { return RomInfo(plain: nil, label: "ROM chiffrée d'Amiga Forever : il faut son fichier rom.key dans le dossier", tags: []) }
            let src = [UInt8](b.dropFirst(11)), kb = [UInt8](k)
            var out = [UInt8](repeating: 0, count: src.count)
            for i in 0..<src.count { out[i] = src[i] ^ kb[i % kb.count] }
            p = Data(out)
        }
        guard [262144, 524288, 1048576].contains(p.count) else { return nil }
        let bytes = [UInt8](p.prefix(256))
        // AROS : déjà intégré, il ressemble à un Kickstart 3.1.4 mais n'en est pas un
        if (String(bytes: bytes, encoding: .isoLatin1) ?? "").contains("AROS") { return RomInfo(plain: p, label: "AROS, déjà intégré à l'application", tags: [], aros: true) }
        let crc = Kickstarts.crc32(p)
        if let k = Kickstarts.known[crc] {
            var tags: Set<String> = []
            if k.cdtvExt { tags.insert("cdtvext") }
            else if k.models.contains("CD32") { tags.insert(crc == cd32Ext ? "cd32ext" : "cd32main") }
            else {
                if k.models.contains("A1200") { tags.insert("a1200") }
                if k.label.hasPrefix("Kickstart 1.3") { tags.insert("a500") }
            }
            return RomInfo(plain: p, label: k.label, tags: tags)
        }
        var v = 0
        if bytes[0] == 0x11 && [0x11, 0x14, 0x16].contains(bytes[1]) {
            v = Int(bytes[12]) << 8 | Int(bytes[13])
            if !(30...60).contains(v) { v = 0 }
        }
        if v == 0 { return nil }
        // ROM de 1 Mo non répertoriée : la ROM complète d'une CD32
        if p.count == 1048576 { return RomInfo(plain: p, label: "ROM CD32 complète (1 Mo)", tags: ["cd32main"]) }
        return RomInfo(plain: p, label: "Kickstart \(Kickstarts.family(v)) (\(v))", tags: v == 34 ? ["a500"] : v >= 39 ? ["a1200"] : [])
    }

    private static func firstMatch(_ pattern: String, _ text: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .anchorsMatchLines]),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: text).map { String(text[$0]) } ?? "" }
    }
    private static func cueTracks(_ text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: "^\\s*FILE\\s+(?:\"([^\"]+)\"|(\\S+))", options: [.caseInsensitive, .anchorsMatchLines]) else { return [] }
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { m in
            let r = m.range(at: 1).location != NSNotFound ? m.range(at: 1) : m.range(at: 2)
            guard let rr = Range(r, in: text) else { return nil }
            return String(text[rr]).components(separatedBy: CharacterSet(charactersIn: "/\\")).last
        }
    }

    /// Reconnaissance de chaque fichier, doublons compris (Bibliothèque, Kickstart installés, configurations)
    static func classify(_ s: Settings, _ items: [Item], _ stop: Stop, _ progress: (Int, String) -> Void) {
        let norm = { (k: String) in k == Library.whdhdf ? Library.hdf : k }
        let lib = Set(Library.all().map { norm($0.kind) + "|" + $0.name.lowercased() })
        var roms = Set(Kickstarts.list().map(\.crc))
        for n in ["cd32.rom", "cd32ext.rom"] { if let d = FileManager.default.contents(atPath: Paths.sys.appendingPathComponent(n).path) { roms.insert(Kickstarts.crc32(d)) } }
        let configs = Set(s.configs.keys.map { $0.lowercased() })
        let romKey = items.first { $0.name.lowercased().hasSuffix(".key") && $0.size > 0 && $0.size < 65536 }.flatMap { FileManager.default.contents(atPath: $0.path) }
        var byDir: [String: [Item]] = [:]
        for it in items { byDir[(it.path as NSString).deletingLastPathComponent, default: []].append(it) }
        var seen = Set<String>()
        var tracks = Set<String>()
        for (i, it) in items.enumerated() {
            if stop.stop { break }
            if i % 10 == 0 { progress(i, it.rel) }
            let n = it.name.lowercased(), ext = (n as NSString).pathExtension
            switch ext {
            case "key":
                if it.size > 0 && it.size < 65536 { it.kind = key; it.why = "sert à lire les ROM chiffrées d'Amiga Forever du dossier" }
            case "adf", "adz", "dms", "ipf", "scp":
                it.kind = Library.floppy
            case "lha", "lzh":
                if hasSlave(it.path) { it.kind = Library.whd }
            case "hdf", "hdz", "vhd":
                it.kind = Library.hdf
                if ZipImport.bootsWhdload(it.path) { it.kind = Library.whdhdf; it.label = "jeu WHDLoad sur disque dur (▶ Jouer)" }
            case "iso", "chd":
                it.kind = Library.cd
            case "cue":
                guard it.size > 0 && it.size < 65536, let text = (try? String(contentsOfFile: it.path, encoding: .isoLatin1)) else { break }
                let wanted = cueTracks(text)
                if wanted.isEmpty { break }
                it.kind = Library.cd
                let pool = byDir[(it.path as NSString).deletingLastPathComponent] ?? []
                let missing = wanted.filter { w in !pool.contains { $0.name.lowercased() == w.lowercased() } }
                for p in pool where wanted.contains(where: { $0.lowercased() == p.name.lowercased() }) { tracks.insert(p.path) }
                if !missing.isEmpty { it.why = "pistes absentes du dossier : " + missing.joined(separator: ", ") }
            case "uae":
                guard it.size > 0 && it.size < 1 << 20 else { break }
                it.kind = uae
                let text = (try? String(contentsOfFile: it.path, encoding: .isoLatin1)) ?? ""
                let d = firstMatch("^\\s*config_description\\s*=\\s*(.+?)\\s*$", text)?[1] ?? ""
                it.label = String((d.isEmpty ? (it.name as NSString).deletingPathExtension : d).prefix(60))
                if configs.contains(it.label.lowercased()) { it.why = "déjà dans les configurations" }
            case "zip":
                if let k = zipKind(it.path) {
                    it.kind = k
                    it.label = k == zip ? "disque dur ou jeu à extraire" : k == Library.whd ? "dossier d'un jeu WHDLoad" : "disquette zippée"
                }
            default:
                break
            }
            if n.hasSuffix(".adf.gz") { it.kind = Library.floppy }
            // Kickstart : .rom, .bin, ou un fichier de la taille d'une ROM
            if it.kind == nil && ((["rom", "bin"].contains(ext) && it.size > 0 && it.size <= 2 * 1048576 + 11)
                || [262144, 524288, 1048576, 262155, 524299, 1048587].contains(it.size)),
               let b = FileManager.default.contents(atPath: it.path), let info = romInfo(b, romKey) {
                it.kind = Library.rom; it.label = info.label; it.tags = info.tags; it.rom = info.plain
                if info.aros { it.why = "inutile" }
                else if let p = info.plain {
                    let c = Kickstarts.crc32(p)
                    if roms.contains(c) { it.why = "déjà installé" }
                    else if !seen.insert("rom|\(c)").inserted { it.why = "en double dans le dossier" }
                } else { it.why = "illisible sans rom.key" }
            }
            guard let k = it.kind else { continue }
            if [Library.floppy, Library.whd, Library.whdhdf, Library.hdf, Library.cd, zip].contains(k) && it.why.isEmpty {
                let id = norm(k == zip ? Library.floppy : k) + "|" + n
                // Empreinte des disquettes et des jeux (petits fichiers) : même contenu sous un autre nom
                var c = ""
                if (k == Library.floppy || k == Library.whd) && it.size < 64 << 20, let d = FileManager.default.contents(atPath: it.path) { c = "crc|\(Kickstarts.crc32(d))" }
                if lib.contains(id) || (k == zip && (lib.contains(Library.hdf + "|" + n) || lib.contains(Library.whd + "|" + n))) {
                    it.why = "déjà dans la Bibliothèque"
                    if !c.isEmpty { seen.insert(c) }
                } else if !seen.insert(id).inserted || (!c.isEmpty && !seen.insert(c).inserted) { it.why = "en double dans le dossier" }
            }
            if !it.why.isEmpty { it.on = false }
        }
        // Les pistes d'un .cue ne comptent pas à part
        for it in items where it.kind == nil && tracks.contains(it.path) { it.why = "piste" }
    }

    /// Usages couverts par les Kickstart déjà installés
    static func libTags() -> Set<String> {
        var t: Set<String> = []
        for r in Kickstarts.list() {
            if r.cdtvExt { t.insert("cdtvext"); continue }
            if r.models.contains("CD32") { continue }
            if Kickstarts.fits(r, "A1200") { t.insert("a1200") }
            if r.version == 34 || r.label.hasPrefix("Kickstart 1.3") { t.insert("a500") }
        }
        if Kickstarts.cd32Rom { t.insert("cd32main") }
        return t
    }
    static func kickLine(_ t: Set<String>) -> String {
        [("Amiga 1200 (3.x)", "a1200"), ("Amiga 500 (1.3)", "a500"), ("CD32", "cd32main"), ("CDTV (extension)", "cdtvext")]
            .map { (t.contains($0.1) ? "✓ " : "✗ ") + $0.0 }.joined(separator: " · ")
    }

    struct Report { var added: [(String, Int)] = []; var notes: [String] = [] }

    /// Ajout de ce qui est coché : Kickstart installés, le reste rangé dans la Bibliothèque (lu sur place).
    /// Les configurations .uae sont enregistrées ensuite, par l'accueil (réglages de l'application).
    static func importAll(_ items: [Item], _ stop: Stop, _ progress: (Int, Int, String) -> Void) -> Report {
        var r = Report()
        var counts: [String: Int] = [:], order: [String] = []
        func count(_ k: String) { if counts[k] == nil { order.append(k) }; counts[k, default: 0] += 1 }
        let todo = items.filter { $0.kind != nil && $0.on && $0.why.isEmpty }
        for (i, it) in todo.enumerated() {
            if stop.stop { break }
            progress(i, todo.count, it.rel)
            guard let k = it.kind else { continue }
            switch k {
            case Library.rom:
                guard let p = it.rom else { continue }
                if it.tags.contains("cd32main") || it.tags.contains("cd32ext") {
                    try? p.write(to: Paths.sys.appendingPathComponent(it.tags.contains("cd32ext") ? "cd32ext.rom" : "cd32.rom")); count(k)
                } else if Kickstarts.installData(p) != nil { count(k) }
                else { r.notes.append("\(it.name) : pas la taille d'un Kickstart") }
            case zip:
                let res = ZipImport.inspect(it.path)
                for f in res.found { Library.add(f.path, kind: f.kind) }
                if let p = res.problem { r.notes.append(p) }
                if res.whdArchive { Library.add(it.path, kind: Library.whd) }
                else if res.found.isEmpty && res.problem == nil { Library.add(it.path, kind: Library.floppy) }
                if !res.found.isEmpty || res.whdArchive { count(k) }
            case uae:
                count(k)
            default:
                if Library.add(it.path, kind: k) { count(k) }
            }
        }
        r.added = order.map { ($0, counts[$0] ?? 0) }
        return r
    }

    static let cats: [(String, String)] = [(Library.rom, "Kickstart et ROM"), (key, "Clé rom.key (Amiga Forever)"), (Library.floppy, "Disquettes"),
        (Library.whd, "Jeux WHDLoad"), (zip, "Archives .zip (disques durs, jeux)"), (Library.hdf, "Disques durs"),
        (Library.cd, "CD (CD32, CDTV)"), (uae, "Configurations .uae")]
    static func cat(_ k: String?) -> String? { k == Library.whdhdf ? Library.whd : k }
    static let names: [String: (String, String)] = [Library.rom: ("Kickstart ou ROM", "Kickstart ou ROM"), Library.floppy: ("disquette", "disquettes"),
        Library.whd: ("jeu WHDLoad", "jeux WHDLoad"), Library.whdhdf: ("jeu WHDLoad sur disque dur", "jeux WHDLoad sur disque dur"),
        zip: ("archive", "archives"), Library.hdf: ("disque dur", "disques durs"), Library.cd: ("CD", "CD"), uae: ("configuration", "configurations")]
}

/// Case à cocher qui appelle une fonction
final class ClosureCheck: NSButton {
    private var handler: ((Bool) -> Void)?
    convenience init(_ title: String, _ f: @escaping (Bool) -> Void) {
        self.init(frame: .zero)
        setButtonType(.switch); self.title = title; handler = f
        target = self; action = #selector(fire)
    }
    @objc private func fire() { handler?(state == .on) }
}

extension HomeDelegate {
    /// Scanner un dossier : choix du dossier, analyse, bilan à cocher, ajout
    func scanFolder() {
        let p = NSOpenPanel()
        p.message = "Dossier à scanner (Amiga Forever, clé USB, votre dossier Amiga…) : ses sous-dossiers sont parcourus aussi"
        p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false
        p.prompt = "Scanner"
        guard p.runModal() == .OK, let root = p.url else { return }
        let stop = Scan.Stop()
        let (sheet, label) = scanProgress("Scanner « \(root.lastPathComponent) »", stop)
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let items = Scan.walk(root, stop) { n in DispatchQueue.main.async { label.stringValue = "Recherche des fichiers… \(n) trouvés" } }
            Scan.classify(s, items, stop) { i, rel in DispatchQueue.main.async { label.stringValue = "Analyse : \(i + 1) / \(items.count)\n\(rel)" } }
            DispatchQueue.main.async { [self] in
                window.endSheet(sheet.window)
                scanSummary(root.lastPathComponent, items, stopped: stop.stop)
            }
        }
    }

    /// Fenêtre d'avancée, en feuille sur l'accueil, avec « Arrêter »
    private func scanProgress(_ title: String, _ stop: Scan.Stop) -> (NSAlert, NSTextField) {
        let a = NSAlert()
        a.messageText = title
        let label = NSTextField(wrappingLabelWithString: "Recherche des fichiers…")
        label.frame = NSRect(x: 0, y: 0, width: 420, height: 48)
        a.accessoryView = label
        a.addButton(withTitle: "Arrêter")
        a.beginSheetModal(for: window) { r in if r == .alertFirstButtonReturn { stop.stop = true } }
        return (a, label)
    }

    private func scanSummary(_ dir: String, _ items: [Scan.Item], stopped: Bool) {
        let found = items.filter { $0.kind != nil }
        let ignored = items.filter { $0.kind == nil && $0.why != "piste" }.count
        let a = NSAlert()
        a.messageText = "Scanner « \(dir) »"
        a.informativeText = "\(items.count) fichier\(items.count > 1 ? "s" : ""), \(found.count) reconnu\(found.count > 1 ? "s" : "")"
            + (ignored > 0 ? " (\(ignored) autre\(ignored > 1 ? "s" : "") ignoré\(ignored > 1 ? "s" : ""))" : "") + (stopped ? ". Analyse arrêtée avant la fin." : ".")
        if found.isEmpty {
            a.informativeText += "\n\nAucun fichier Amiga reconnu ici. Essayez un autre dossier, ou le dossier parent."
            a.addButton(withTitle: "Autre dossier…"); a.addButton(withTitle: "Fermer")
            if a.runModal() == .alertFirstButtonReturn { scanFolder() }
            return
        }
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 4
        let kicks = NSTextField(wrappingLabelWithString: "")
        kicks.preferredMaxLayoutWidth = 540
        stack.addArrangedSubview(kicks)
        let warn = NSTextField(wrappingLabelWithString: "Les jeux WHDLoad demandent votre Kickstart 3.1 de l'A1200 (AROS ne leur suffit pas) ; certains jeux A500 veulent aussi le 1.3.")
        warn.preferredMaxLayoutWidth = 540; warn.textColor = .secondaryLabelColor
        stack.addArrangedSubview(warn)
        a.addButton(withTitle: "Ajouter"); a.addButton(withTitle: "Autre dossier…"); a.addButton(withTitle: "Fermer")
        let base = Scan.libTags()
        func update() {
            let t = base.union(found.filter { $0.kind == Library.rom && $0.on }.flatMap { $0.tags })
            kicks.stringValue = "Kickstart après l'ajout : " + Scan.kickLine(t)
            warn.isHidden = !(found.contains { Scan.cat($0.kind) == Library.whd && $0.on } && !t.contains("a1200"))
            let n = found.filter(\.on).count
            a.buttons[0].title = n > 0 ? "Ajouter (\(n))" : "Rien à ajouter"
            a.buttons[0].isEnabled = n > 0
        }
        for (kind, title) in Scan.cats {
            let list = found.filter { Scan.cat($0.kind) == kind }
            if list.isEmpty { continue }
            let fresh = list.filter { $0.why.isEmpty }.count, other = list.count - fresh
            var rows: [(ClosureCheck, Scan.Item)] = []
            let head = ClosureCheck("\(title) : \(fresh)" + (other > 0 ? " (+\(other) déjà là ou non importable\(other > 1 ? "s" : ""))" : "")) { on in
                for (c, x) in rows where x.why.isEmpty { c.state = on ? .on : .off; x.on = on }
                for x in list.dropFirst(300) where x.why.isEmpty { x.on = on }
                update()
            }
            head.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
            head.state = list.contains { $0.on } ? .on : .off
            head.isEnabled = fresh > 0
            stack.addArrangedSubview(head)
            for it in list.prefix(300) {
                let detail = [it.label, it.why].filter { !$0.isEmpty }.joined(separator: " · ")
                let c = ClosureCheck(it.rel + (detail.isEmpty ? "" : "  —  " + detail)) { on in
                    it.on = on; head.state = list.contains { $0.on } ? .on : .off; update()
                }
                c.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
                c.state = it.on ? .on : .off; c.isEnabled = it.why.isEmpty
                c.lineBreakMode = .byTruncatingMiddle
                c.widthAnchor.constraint(lessThanOrEqualToConstant: 540).isActive = true
                let indent = NSStackView(views: [c]); indent.edgeInsets = NSEdgeInsets(top: 0, left: 18, bottom: 0, right: 0)
                stack.addArrangedSubview(indent)
                rows.append((c, it))
            }
            if list.count > 300 { stack.addArrangedSubview(NSTextField(labelWithString: "      … et \(list.count - 300) autres")) }
        }
        let foot = NSTextField(wrappingLabelWithString: "Les fichiers restent où ils sont : l'application les lit sur place. Les Kickstart sont installés comme ROM de la machine.")
        foot.preferredMaxLayoutWidth = 540; foot.textColor = .secondaryLabelColor
        stack.addArrangedSubview(foot)
        stack.layoutSubtreeIfNeeded()
        let fit = stack.fittingSize
        stack.frame = NSRect(x: 0, y: 0, width: 560, height: fit.height)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 580, height: min(420, fit.height + 4)))
        scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let flipped = FlippedView(frame: stack.frame); flipped.addSubview(stack)
        scroll.documentView = flipped
        a.accessoryView = scroll
        update()
        switch a.runModal() {
        case .alertFirstButtonReturn: scanImport(items)
        case .alertSecondButtonReturn: scanFolder()
        default: break
        }
    }

    private func scanImport(_ items: [Scan.Item]) {
        let stop = Scan.Stop()
        let (sheet, label) = scanProgress("Ajout à la Bibliothèque", stop)
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let r = Scan.importAll(items, stop) { i, n, rel in DispatchQueue.main.async { label.stringValue = "\(i + 1) / \(n)\n\(rel)" } }
            DispatchQueue.main.async { [self] in
                window.endSheet(sheet.window)
                // Configurations .uae : enregistrées sous leur nom, sans changer la machine en cours
                for it in items where it.kind == Scan.uae && it.on && it.why.isEmpty {
                    let keep = s.snapshot()
                    _ = ConfigsIO.import(s, from: URL(fileURLWithPath: it.path))
                    var c = s.configs; c[it.label.isEmpty ? (it.name as NSString).deletingPathExtension : it.label] = s.snapshot(); s.configs = c
                    s.restore(keep)
                }
                if r.added.contains(where: { $0.0 == Library.rom }) && s.rom == "aros" && Kickstarts.best("A1200") != nil { s.rom = "user" }
                refresh()
                let parts = r.added.map { k, n in "\(n) " + (Scan.names[k].map { n > 1 ? $0.1 : $0.0 } ?? k) }
                var msg = parts.isEmpty ? "Rien n'a été ajouté." : "Ajouté : " + parts.joined(separator: ", ") + "."
                if stop.stop { msg += "\n\nAjout arrêté avant la fin." }
                if !r.notes.isEmpty { msg += "\n\n" + r.notes.prefix(30).joined(separator: "\n") }
                let a = NSAlert(); a.messageText = "Scan terminé"; a.informativeText = msg
                a.addButton(withTitle: "OK"); a.addButton(withTitle: "Autre dossier…")
                if a.runModal() == .alertSecondButtonReturn { scanFolder() }
            }
        }
    }
}

/// Vue à l'origine en haut (liste qui défile depuis le début)
final class FlippedView: NSView { override var isFlipped: Bool { true } }
