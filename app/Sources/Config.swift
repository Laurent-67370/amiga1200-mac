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
    static var kick: URL { sys.appendingPathComponent("kick.rom") }
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

    var model: String { get { d.string(forKey: "model") ?? "A1200" } set { d.set(newValue, forKey: "model") } }
    var jit: Bool { get { d.object(forKey: "jit") as? Bool ?? true } set { d.set(newValue, forKey: "jit") } }
    var rtg: Bool { get { d.object(forKey: "rtg") as? Bool ?? true } set { d.set(newValue, forKey: "rtg") } }
    var ntsc: Bool { get { d.bool(forKey: "ntsc") } set { d.set(newValue, forKey: "ntsc") } }
    var shared: Bool { get { d.object(forKey: "shared") as? Bool ?? true } set { d.set(newValue, forKey: "shared") } }
    var floppySound: Bool { get { d.object(forKey: "floppySound") as? Bool ?? true } set { d.set(newValue, forKey: "floppySound") } }
    /// Image nette (pixels francs) au lieu de lisse
    var sharp: Bool { get { d.bool(forKey: "sharp") } set { d.set(newValue, forKey: "sharp") } }
    /// « user » : Kickstart copié dans sys/kick.rom ; « aros » : ROM libre fournie
    var rom: String { get { d.string(forKey: "rom") ?? "aros" } set { d.set(newValue, forKey: "rom") } }
    var romName: String { get { d.string(forKey: "romName") ?? "" } set { d.set(newValue, forKey: "romName") } }
    var df0: String { get { d.string(forKey: "df0") ?? "" } set { d.set(newValue, forKey: "df0") } }
    var df1: String { get { d.string(forKey: "df1") ?? "" } set { d.set(newValue, forKey: "df1") } }
    /// Disques durs DH0: à DH7: (chemins), le premier démarre
    var hds: [String] { get { d.stringArray(forKey: "hds") ?? [] } set { d.set(newValue, forKey: "hds") } }

    var userRom: Bool { rom == "user" && FileManager.default.fileExists(atPath: Paths.kick.path) }
    static func bigBox(_ m: String) -> Bool { m == "A1200" || m == "A4000" }
    static func isWhd(_ path: String) -> Bool { ["lha", "lzh", "lzx"].contains((path as NSString).pathExtension.lowercased()) }
}

/// Configuration WinUAE écrite pour Amiberry (même principe que Config.write de la version Android)
enum Config {
    /// Contenu à donner au cœur : une archive WHDLoad en DF0: se lance seule, sinon la configuration .uae
    static func content(_ s: Settings = .shared) -> String {
        if Settings.isWhd(s.df0) { return s.df0 }
        return write(s).path
    }

    @discardableResult
    static func write(_ s: Settings, arosOnly: Bool = false) -> URL {
        let model = s.model
        var l = ["quickstart=\(model),0"]
        if s.userRom && !arosOnly {
            l.append("kickstart_rom_file=\(Paths.kick.path)")
        } else {
            l.append("kickstart_rom_file=\(Paths.sys.appendingPathComponent("aros-rom.bin").path)")
            l.append("kickstart_ext_rom_file=\(Paths.sys.appendingPathComponent("aros-ext.bin").path)")
            // AROS ne tient pas dans la mémoire d'un A500 ou d'un A600
            if model == "A500" { l.append("fastmem_size=2") }
            if model == "A600" { l.append("fastmem_size=4") }
        }
        l += ["nr_floppies=2", "floppy1type=0"]
        if !s.df0.isEmpty && !arosOnly { l.append("floppy0=\(s.df0)") }
        if !s.df1.isEmpty && !arosOnly { l.append("floppy1=\(s.df1)") }
        if s.floppySound { l += ["floppy0sound=1", "floppy1sound=1"] }
        if s.jit && Settings.bigBox(model) {
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
        if s.rtg && Settings.bigBox(model) {
            l += ["gfxcard_type=ZorroIII", "gfxcard_size=32"]
            if !s.jit && model == "A1200" { l += ["cpu_model=68020", "cpu_24bit_addressing=false"] }
        }
        let hds = arosOnly ? [] : s.hds
        for (i, p) in hds.prefix(8).enumerated() {
            l.append("hardfile2=rw,DH\(i):\(p),0,0,0,512,\(i == 0 ? 0 : -1),,uae\(i)")
        }
        if !hds.isEmpty && s.shared { l.append("filesystem2=rw,DH12:SHARED:\(Paths.shared.path),-128") }
        let f = arosOnly ? Paths.dir("cfg").appendingPathComponent("essai.uae") : Paths.config
        try? (l.joined(separator: "\n") + "\n").write(to: f, atomically: true, encoding: .utf8)
        amb_log("Configuration :\n" + l.joined(separator: "\n"))
        return f
    }
}
