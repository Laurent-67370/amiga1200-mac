import Foundation

/// Dossiers de l'application : réglages, ROM, sauvegardes dans ~/Library/Application Support/Amiga1200 ;
/// volume SHARED: visible dans ~/Documents/Amiga1200/SHARED.
enum Paths {
    static let support: URL = {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Amiga1200")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()
    static func dir(_ name: String) -> URL {
        let u = support.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static var sys: URL { dir("sys") }
    static var save: URL { dir("save") }
    static var data: URL { dir("data") }
    static var log: URL { support.appendingPathComponent("journal.txt") }
    static var config: URL { dir("cfg").appendingPathComponent("amiga.uae") }
    static var shared: URL {
        let u = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Amiga1200/SHARED")
        try? FileManager.default.createDirectory(at: u.appendingPathComponent("SaveGames"), withIntermediateDirectories: true)
        return u
    }
    static var resources: URL { Bundle.main.resourceURL ?? URL(fileURLWithPath: ".") }

    /// Ressources copiées une fois par version : ROM AROS, WHDLoad d'Amiberry, bruits des lecteurs
    static func installResources() {
        let fm = FileManager.default
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        let stamp = support.appendingPathComponent(".ressources")
        if (try? String(contentsOf: stamp, encoding: .utf8)) == version { return }
        for n in ["aros-rom.bin", "aros-ext.bin"] {
            let d = sys.appendingPathComponent(n)
            try? fm.removeItem(at: d)
            try? fm.copyItem(at: resources.appendingPathComponent("aros/\(n)"), to: d)
        }
        let sounds = data.appendingPathComponent("floppy_sounds")
        try? fm.removeItem(at: sounds)
        try? fm.copyItem(at: resources.appendingPathComponent("floppy_sounds"), to: sounds)
        copyTree(resources.appendingPathComponent("whdboot"), save.appendingPathComponent("WHDBoot"))
        for d in ["Autoboots", "Debugs", "Kickstarts", "Savegames"] {
            try? fm.createDirectory(at: save.appendingPathComponent("WHDBoot/save-data/\(d)"), withIntermediateDirectories: true)
        }
        try? version.write(to: stamp, atomically: true, encoding: .utf8)
    }

    /// Copie d'un dossier ; les sauvegardes des jeux (save-data) déjà présentes ne sont pas écrasées
    private static func copyTree(_ src: URL, _ dst: URL) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: src.path, isDirectory: &isDir) else { return }
        if !isDir.boolValue {
            if fm.fileExists(atPath: dst.path) {
                if dst.path.contains("/save-data/") { return }
                try? fm.removeItem(at: dst)
            }
            try? fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.copyItem(at: src, to: dst)
            return
        }
        for n in (try? fm.contentsOfDirectory(atPath: src.path)) ?? [] {
            copyTree(src.appendingPathComponent(n), dst.appendingPathComponent(n))
        }
    }
}

/// Réglages, gardés par macOS (UserDefaults) et relus par le processus de l'émulation
final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    /// A500, A600, A1200, A3000, A4000, CD32 ou CDTV
    var model: String { get { d.string(forKey: "model") ?? "A1200" } set { d.set(newValue, forKey: "model"); saveProfile() } }
    var jit: Bool { get { d.object(forKey: "jit") as? Bool ?? true } set { d.set(newValue, forKey: "jit"); saveProfile() } }
    var rtg: Bool { get { d.object(forKey: "rtg") as? Bool ?? true } set { d.set(newValue, forKey: "rtg"); saveProfile() } }
    var ntsc: Bool { get { d.bool(forKey: "ntsc") } set { d.set(newValue, forKey: "ntsc") } }
    var shared: Bool { get { d.object(forKey: "shared") as? Bool ?? true } set { d.set(newValue, forKey: "shared") } }
    var floppySound: Bool { get { d.object(forKey: "floppySound") as? Bool ?? true } set { d.set(newValue, forKey: "floppySound") } }
    /// Image nette (pixels francs) au lieu de lisse
    var sharp: Bool { get { d.bool(forKey: "sharp") } set { d.set(newValue, forKey: "sharp") } }
    /// « user » : Kickstart installés, choisi selon la machine (voir Kickstarts) ; « aros » : ROM libre fournie
    var rom: String { get { d.string(forKey: "rom") ?? "aros" } set { d.set(newValue, forKey: "rom") } }
    var romName: String { get { d.string(forKey: "romName") ?? "" } set { d.set(newValue, forKey: "romName") } }
    var df0: String { get { d.string(forKey: "df0") ?? "" } set { d.set(newValue, forKey: "df0") } }
    var df1: String { get { d.string(forKey: "df1") ?? "" } set { d.set(newValue, forKey: "df1") } }
    /// Disques durs DH0: à DH7: (chemins), le premier démarre
    var hds: [String] { get { d.stringArray(forKey: "hds") ?? [] } set { d.set(newValue, forKey: "hds") } }
    /// CD de la CD32 ou du CDTV (image .iso ou .chd)
    var cd: String { get { d.string(forKey: "cd") ?? "" } set { d.set(newValue, forKey: "cd") } }
    /// Mémoire Chip en blocs de 512 Ko (0 : celle du modèle ; 1 = 512 Ko, 2 = 1 Mo, 4 = 2 Mo)
    var chip: Int { get { d.object(forKey: "chip") as? Int ?? 0 } set { d.set(newValue, forKey: "chip"); saveProfile() } }
    /// Mémoire Slow (« trappe » de l'A500) en blocs de 256 Ko (-1 : celle du modèle ; 0, 2 = 512 Ko, 4 = 1 Mo)
    var slow: Int { get { d.object(forKey: "slow") as? Int ?? -1 } set { d.set(newValue, forKey: "slow"); saveProfile() } }
    /// Mémoire Fast Zorro II en Mo (0, 2, 4, 8 ; pas avec le JIT, qui a déjà 64 Mo de Zorro III)
    var fast: Int { get { d.object(forKey: "fast") as? Int ?? 0 } set { d.set(newValue, forKey: "fast"); saveProfile() } }
    /// Carte accélératrice sans JIT (A1200, A3000, A4000) : « none », « 030 » (68030/68882) ou « 040 »
    var accel: String { get { d.string(forKey: "accel") ?? "none" } set { d.set(newValue, forKey: "accel"); saveProfile() } }

    // ---------- réglages retenus par disque de démarrage ----------
    /// Disque qui démarre : le CD des consoles, sinon la disquette DF0:, sinon le premier disque dur
    func bootKey() -> String {
        let p = Settings.cdConsole(model) ? cd : !df0.isEmpty ? df0 : hds.first ?? ""
        return (p as NSString).lastPathComponent
    }
    private static let profileKeys = ["model", "jit", "rtg", "chip", "slow", "fast", "accel"]
    private func saveProfile() {
        let k = bootKey()
        if k.isEmpty { return }
        var p: [String: Any] = [:]
        for key in Settings.profileKeys { if let v = d.object(forKey: key) { p[key] = v } }
        d.set(p, forKey: "profil:" + k)
    }
    /// Reprend la machine, la mémoire et le processeur retenus pour le disque de démarrage ; vrai s'ils existaient
    @discardableResult
    func applyProfile() -> Bool {
        guard let p = d.dictionary(forKey: "profil:" + bootKey()) else { return false }
        for key in Settings.profileKeys { d.set(p[key], forKey: key) }
        return true
    }

    // ---------- configurations enregistrées ----------
    private static let snapshotKeys = ["model", "jit", "rtg", "ntsc", "shared", "chip", "slow", "fast", "accel", "df0", "df1", "hds", "cd"]
    /// Machine et disques, pour une configuration enregistrée sous un nom
    func snapshot() -> [String: Any] {
        var o: [String: Any] = [:]
        for key in Settings.snapshotKeys { if let v = d.object(forKey: key) { o[key] = v } }
        return o
    }
    func restore(_ o: [String: Any]) { for key in Settings.snapshotKeys { d.set(o[key], forKey: key) } }
    var configs: [String: [String: Any]] {
        get { d.dictionary(forKey: "configs") as? [String: [String: Any]] ?? [:] }
        set { d.set(newValue, forKey: "configs") }
    }

    // ---------- reprise où l'on en était ----------
    /// Signature de la configuration : la reprise n'est proposée qu'avec la même machine et les mêmes disques
    func signature() -> String {
        [model, "\(jit)", "\(rtg)", "\(ntsc)", rom, romName, df0, df1, cd, hds.joined(separator: "|"), "\(chip)", "\(slow)", "\(fast)", accel].joined(separator: "#")
    }
    var resumeSig: String { get { d.string(forKey: "resumeSig") ?? "" } set { d.set(newValue, forKey: "resumeSig") } }
    /// Jeu lancé directement dont l'état est gardé : « whd » ou « hdf », son chemin et son nom (lignes) ; vide pour la
    /// machine de l'accueil
    var resumeGame: String { get { d.string(forKey: "resumeGame") ?? "" } set { d.set(newValue, forKey: "resumeGame") } }
    /// État de « Reprendre où j'en étais » (une seule fois)
    static var resumeFile: URL { Paths.save.appendingPathComponent("reprise.uss") }

    /// Kickstart utilisé pour cette machine (nil : AROS)
    func kick(_ model: String) -> Rom? { rom == "user" ? Kickstarts.best(model) : nil }
    /// Machines : A1200, A3000 et A4000 acceptent le JIT et la carte RTG ; la CD32 et le CDTV démarrent sur leur CD
    static func bigBox(_ m: String) -> Bool { m == "A1200" || m == "A3000" || m == "A4000" }
    static func cdConsole(_ m: String) -> Bool { m == "CD32" || m == "CDTV" }
    static func isWhd(_ path: String) -> Bool { ["lha", "lzh", "lzx"].contains((path as NSString).pathExtension.lowercased()) }
}

/// Configuration WinUAE écrite pour Amiberry (même logique que Config.write de la version Android)
enum Config {
    /// Contenu à donner au cœur : une archive WHDLoad en DF0: se lance seule, sinon la configuration .uae
    static func content(_ s: Settings = .shared) -> String {
        if Settings.isWhd(s.df0) { return s.df0 }
        return write(s).path
    }

    /// Disque dur avec table de partitions (RDB, comme AGS) ; sinon l'image d'une seule partition, qui demande sa
    /// géométrie (32 secteurs, 1 tête, 2 blocs réservés, comme le cœur pour un .hdf lancé seul)
    static func hasRdb(_ path: String) -> Bool {
        guard let h = FileHandle(forReadingAtPath: path) else { return true }
        defer { try? h.close() }
        let b = h.readData(ofLength: 16 * 512)
        return (0..<(b.count / 512)).contains { k in b.subdata(in: k * 512 ..< k * 512 + 4) == Data("RDSK".utf8) }
    }

    /// Noms des images de Kickstart pour WHDLoad (paquet skick), d'après la somme CRC32
    private static let whdKickNames: [UInt32: String] = [
        0xA6CE1636: "kick33180.A500", 0xC4F0F55F: "kick34005.A500", 0xC3BDB240: "kick37175.A500",
        0xFC24AE0D: "kick40063.A600", 0x6C9B07D2: "kick39106.A1200", 0x1483A091: "kick40068.A1200",
        0xD6BAE334: "kick40068.A4000",
    ]

    /// Dossier WHDCommon/Kickstarts : vos Kickstart sous les noms qu'attend WHDLoad et les tables de relogement (.RTB)
    /// d'Amiberry ; nil sans Kickstart reconnu
    static func whdCommon() -> URL? {
        let fm = FileManager.default
        let roms = Kickstarts.list().filter { whdKickNames[$0.crc] != nil }
        if roms.isEmpty { return nil }
        let root = Paths.dir("whdcommon"), dir = root.appendingPathComponent("Kickstarts")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for r in roms {
            let f = dir.appendingPathComponent(whdKickNames[r.crc]!)
            if !fm.fileExists(atPath: f.path) { try? fm.copyItem(atPath: r.path, toPath: f.path) }
        }
        let rtb = Paths.save.appendingPathComponent("WHDBoot/save-data/Kickstarts")
        for n in (try? fm.contentsOfDirectory(atPath: rtb.path)) ?? [] where n.lowercased().hasSuffix(".rtb") {
            let f = dir.appendingPathComponent(n)
            if !fm.fileExists(atPath: f.path) { try? fm.copyItem(at: rtb.appendingPathComponent(n), to: f) }
        }
        return root
    }

    /// [whdHdf] : jeu installé sur un .hdf qui démarre WHDLoad tout seul. Machine de WHDLoad, quelle que soit celle de
    /// l'accueil : A1200 (68020) avec son Kickstart 3.x et 8 Mo de Fast pour le Preload, sans JIT ni carte RTG, ce seul disque
    @discardableResult
    static func write(_ s: Settings, arosOnly: Bool = false, whdHdf: String? = nil) -> URL {
        let sys = Paths.sys
        let model = whdHdf != nil ? "A1200" : s.model
        var l = ["quickstart=\(model),0"]
        let floppies = arosOnly || whdHdf != nil ? ["", ""] : [s.df0, s.df1]
        var hds = arosOnly ? [] : whdHdf.map { [$0] } ?? s.hds
        if model == "CD32" {
            // CD32 : la console telle qu'elle est, avec ses propres ROM (512 Ko + extension, ou ROM complète de 1 Mo)
            l.append("kickstart_rom_file=\(sys.appendingPathComponent("cd32.rom").path)")
            let ext = sys.appendingPathComponent("cd32ext.rom")
            if FileManager.default.fileExists(atPath: ext.path) { l.append("kickstart_ext_rom_file=\(ext.path)") }
            if !s.cd.isEmpty { l.append("cdimage0=\(s.cd),image") }
            l += ["ntsc=\(s.ntsc)", "gfx_resolution=hires"]
            hds = []
        } else if model == "CDTV" {
            // CDTV : la console (68000, ECS, 1 Mo de Chip, sans lecteur de disquettes), son Kickstart (1.3 de préférence)
            // et son extension
            let kick = Kickstarts.best("CDTV")
            s.romName = kick?.label ?? ""
            if let k = kick { l.append("kickstart_rom_file=\(k.path)") }
            if let e = Kickstarts.cdtvExt() { l.append("kickstart_ext_rom_file=\(e.path)") }
            if !s.cd.isEmpty { l.append("cdimage0=\(s.cd),image") }
            l += ["ntsc=\(s.ntsc)", "gfx_resolution=hires"]
            hds = []
        } else {
            // Le Kickstart qui convient à cette machine parmi ceux installés ; sinon AROS
            let kick: Rom? = arosOnly ? nil : whdHdf != nil ? Kickstarts.best(model) : s.kick(model)
            if whdHdf == nil { s.romName = kick?.label ?? "" }
            if let k = kick {
                l.append("kickstart_rom_file=\(k.path)")
            } else {
                l.append("kickstart_rom_file=\(sys.appendingPathComponent("aros-rom.bin").path)")
                l.append("kickstart_ext_rom_file=\(sys.appendingPathComponent("aros-ext.bin").path)")
                // AROS ne tient pas dans la mémoire d'un A500 ou d'un A600
                if model == "A500" { l.append("fastmem_size=2") }
                if model == "A600" { l.append("fastmem_size=4") }
            }
            // Disquette avec un Kickstart 1.x (jeux A500) : les disques durs restent débranchés. Leurs partitions et leurs
            // systèmes de fichiers (AGS…) prendraient la mémoire dont les jeux de l'époque ont besoin (erreur 103)
            if !floppies[0].isEmpty, let k = kick, (1...35).contains(k.version), !hds.isEmpty {
                amb_log("Disquette avec le \(k.label) : disques durs non branchés")
                hds = []
            }
            l += ["nr_floppies=2", "floppy1type=0"]
            for (i, f) in floppies.enumerated() where !f.isEmpty { l.append("floppy\(i)=\(f)") }
            if s.floppySound { l += ["floppy0sound=1", "floppy1sound=1"] }
            if whdHdf != nil { l.append("fastmem_size=8") }
            else if !arosOnly {
                // Mémoire et processeur choisis
                if s.chip > 0 { l.append("chipmem_size=\(s.chip)") }
                if s.slow >= 0 { l.append("bogomem_size=\(s.slow)") }
                // (AROS demande déjà 2 ou 4 Mo à l'A500 et à l'A600 : on garde la plus grande des deux)
                let have = l.filter { $0.hasPrefix("fastmem_size=") }.compactMap { Int($0.dropFirst(13)) }.max() ?? 0
                if s.fast > have && !(s.jit && Settings.bigBox(model)) {
                    l.removeAll { $0.hasPrefix("fastmem_size=") }; l.append("fastmem_size=\(s.fast)")
                }
            }
            let accel = whdHdf == nil && !arosOnly && Settings.bigBox(model) && !s.jit ? s.accel : "none"
            if accel == "030" { l += ["cpu_model=68030", "fpu_model=68882", "cpu_24bit_addressing=false", "cpu_multiplier=8"] }
            if accel == "040" { l += ["cpu_model=68040", "fpu_model=68040", "cpu_24bit_addressing=false", "cpu_multiplier=8"] }
            if s.jit && Settings.bigBox(model) && whdHdf == nil {
                // JIT : 68040 traduit en code ARM64, à pleine vitesse, avec 64 Mo de Fast Zorro III
                l += ["cpu_model=68040", "fpu_model=68040", "cpu_24bit_addressing=false",
                      "cpu_compatible=false", "cycle_exact=false", "cpu_memory_cycle_exact=false", "cpu_speed=max",
                      "cachesize=16384", "compfpu=true", "comp_constjump=true", "comp_flushmode=soft", "comp_nf=true",
                      "comp_trustbyte=direct", "comp_trustword=direct", "comp_trustlong=direct", "comp_trustnaddr=direct",
                      "z3mem_size=64"]
            } else {
                l += ["cycle_exact=false", "cpu_compatible=false"]
            }
            l.append("ntsc=\(s.ntsc)")
            l.append("gfx_resolution=hires")
            // Carte RTG sur le Zorro III : il lui faut un processeur 32 bits (le 68EC020 de l'A1200 n'adresse que 16 Mo)
            if s.rtg && Settings.bigBox(model) && whdHdf == nil {
                l += ["gfxcard_type=ZorroIII", "gfxcard_size=32"]
                if !s.jit && model == "A1200" && accel == "none" { l += ["cpu_model=68020", "cpu_24bit_addressing=false"] }
            }
            // Disques durs sur le pilote d'UAE (uaehf.device) : démarrent AGS et les Workbench préinstallés. Les disques RDB
            // gardent les noms et priorités de démarrage de leurs partitions ; une partition seule reçoit sa géométrie.
            for (i, p) in hds.prefix(8).enumerated() {
                let rdb = hasRdb(p)
                amb_log("\((p as NSString).lastPathComponent) : " + (rdb ? "table de partitions (RDB)" : "partition seule (32 secteurs, 1 tête, 2 blocs réservés)"))
                l.append("hardfile2=rw,DH\(i):\(p),\(rdb ? "0,0,0,512" : "32,1,2,512"),\(i == 0 ? 0 : -1),,uae\(i)")
            }
            if !hds.isEmpty && s.shared && whdHdf == nil { l.append("filesystem2=rw,DH12:SHARED:\(Paths.shared.path),-128") }
            // Jeu WHDLoad sur .hdf : vos Kickstart dans WHDCommon:Kickstarts (WHDLoad y cherche après Devs:Kickstarts)
            if whdHdf != nil, let w = whdCommon() { l.append("filesystem2=ro,DH11:WHDCommon:\(w.path),-128") }
            // Sans disque dur, ni ROM de démarrage ni carte d'UAE, comme la version web : toute la mémoire au jeu
            if hds.isEmpty { l += ["boot_rom_uae=disabled", "uaeboard=disabled"] }
        }
        let f = arosOnly ? Paths.dir("cfg").appendingPathComponent("essai.uae") : Paths.config
        try? (l.joined(separator: "\n") + "\n").write(to: f, atomically: true, encoding: .utf8)
        amb_log("Configuration :\n" + l.joined(separator: "\n"))
        return f
    }
}
