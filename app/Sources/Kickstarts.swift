import Foundation

/// Kickstart installé : fichier dans sys (kick-<crc>.rom), reconnu à son contenu
struct Rom {
    let path: String
    let crc: UInt32
    let version: Int
    let revision: Int
    private var known: Kickstarts.Known? { Kickstarts.known[crc] }
    /// « Kickstart 3.1 (A1200) », ou la version lue dans la ROM
    var label: String {
        if let k = known { return k.label }
        if version > 0 { return "Kickstart \(Kickstarts.family(version)) (\(version).\(revision))" }
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        return "Kickstart (\(size / 1024) Ko)"
    }
    /// Machines pour lesquelles cette ROM est faite, quand elle est connue
    var models: Set<String> { known?.models ?? [] }
    /// ROM d'extension du CDTV (jamais un Kickstart à elle seule)
    var cdtvExt: Bool { known?.cdtvExt == true }
}

/// Plusieurs Kickstart : chacun est choisi automatiquement pour la machine qui lui convient (1.3 pour l'Amiga 500,
/// 3.1 pour l'A1200…), comme la version Android. Ils sont rangés dans sys, où le cœur les retrouve aussi pour WHDLoad.
enum Kickstarts {
    struct Known { let label: String; let models: Set<String>; var cdtvExt = false }

    private static func k(_ label: String, _ models: String...) -> Known { Known(label: label, models: Set(models)) }

    /// ROM de Commodore et d'Hyperion (somme CRC32 du fichier), d'après la table d'Amiberry comme la version web.
    /// « A500 » couvre aussi l'A1000, l'A2000, l'A500+ et le CDTV ; « A4000 » l'A4000T.
    static let known: [UInt32: Known] = [
        0xA6CE1636: k("Kickstart 1.2 (A500)", "A500"),
        0xC4F0F55F: k("Kickstart 1.3 (A500)", "A500"),
        0xE0F37258: k("Kickstart 1.3 (A3000)", "A3000"),
        0xBC0EC13F: k("Kickstart 1.4 (A3000)", "A3000"),
        0xC3BDB240: k("Kickstart 2.04 (A500+)", "A500"),
        0x234A7233: k("Kickstart 2.04 (A3000)", "A3000"),
        0x83028FB5: k("Kickstart 2.05 (A600)", "A600"),
        0x64466C2A: k("Kickstart 2.05 (A600HD)", "A600"),
        0x43B0DF7B: k("Kickstart 2.05 (A600HD)", "A600"),
        0x6C9B07D2: k("Kickstart 3.0 (A1200)", "A1200"),
        0x9E6AC152: k("Kickstart 3.0 (A4000)", "A4000"),
        0xFC24AE0D: k("Kickstart 3.1 (A500, A600, A2000)", "A500", "A600"),
        0x1483A091: k("Kickstart 3.1 (A1200)", "A1200"),
        0xEFB239CC: k("Kickstart 3.1 (A3000)", "A3000"),
        0xD6BAE334: k("Kickstart 3.1 (A4000)", "A4000"),
        0x2B4566F1: k("Kickstart 3.1 (A4000)", "A4000"),
        0x43B6DD22: k("Kickstart 3.1 (A4000)", "A4000"),
        0x75932C3A: k("Kickstart 3.1 (A4000T)", "A4000"),
        0x3AC99EDC: k("Kickstart 3.X (A4000)", "A4000"),
        0xD52B52FD: k("Kickstart 3.1.4 (A500, A600, A2000)", "A500", "A600"),
        0xF17FA97F: k("Kickstart 3.1.4 (A1200)", "A1200"),
        0x50C3529C: k("Kickstart 3.1.4 (A3000)", "A3000"),
        0xD47E18FD: k("Kickstart 3.1.4 (A4000)", "A4000"),
        0x75A2B2A5: k("Kickstart 3.1.4 (A4000T)", "A4000"),
        0x568F8786: k("Kickstart 3.1.4.2 (A500, A600, A2000)", "A500", "A600"),
        0xB87506A7: k("Kickstart 3.1.4.2 (A1200)", "A1200"),
        0xBA35F8EB: k("Kickstart 3.1.4.2 (A3000)", "A3000"),
        0x1B84CB33: k("Kickstart 3.1.4.2 (A4000)", "A4000"),
        0xD6D0EF3E: k("Kickstart 3.1.4.2 (A4000T)", "A4000"),
        0x8173D7B6: k("Kickstart 3.2 (A500, A600, A2000)", "A500", "A600"),
        0xBD1FF75E: k("Kickstart 3.2 (A1200)", "A1200"),
        0xF3AF46CC: k("Kickstart 3.2 (A3000)", "A3000"),
        0x9BB8FC93: k("Kickstart 3.2 (A4000)", "A4000"),
        0x9188A509: k("Kickstart 3.2 (A4000T)", "A4000"),
        0x4F078456: k("Kickstart 3.2.1 (A500, A600, A2000)", "A500", "A600"),
        0x2B653371: k("Kickstart 3.2.1 (A1200)", "A1200"),
        0x0078F607: k("Kickstart 3.2.1 (A3000)", "A3000"),
        0xF3CED3B8: k("Kickstart 3.2.1 (A4000)", "A4000"),
        0xAF3452EC: k("Kickstart 3.2.1 (A4000T)", "A4000"),
        0xE4458462: k("Kickstart 3.2.2 (A500, A600, A2000)", "A500", "A600"),
        0x5C40328A: k("Kickstart 3.2.2 (A1200)", "A1200"),
        0x46335B57: k("Kickstart 3.2.2 (A3000)", "A3000"),
        0x4BEA9798: k("Kickstart 3.2.2 (A4000)", "A4000"),
        0x36BBCD8A: k("Kickstart 3.2.2 (A4000T)", "A4000"),
        0xE1F50B0B: k("Kickstart 3.2.3 (A500, A600, A2000)", "A500", "A600"),
        0xB18D3B67: k("Kickstart 3.2.3 (A1200)", "A1200"),
        0x74C0B23F: k("Kickstart 3.2.3 (A3000)", "A3000"),
        0xB6A4698E: k("Kickstart 3.2.3 (A4000)", "A4000"),
        0x588A5E6D: k("Kickstart 3.2.3 (A4000T)", "A4000"),
        // Extension du CDTV : s'ajoute au Kickstart 1.3 de la console
        0x42BAA124: Known(label: "Extension du CDTV 1.0", models: ["CDTV"], cdtvExt: true),
        0xCEAE68D2: Known(label: "Extension du CDTV 2.7", models: ["CDTV"], cdtvExt: true),
        0x30B54232: Known(label: "Extension du CDTV 2.30", models: ["CDTV"], cdtvExt: true),
        0xAB6274E7: Known(label: "Extension du CDTV 47.1", models: ["CDTV"], cdtvExt: true),
        // ROM de la CD32 : rangées à part (sys/cd32.rom et cd32ext.rom), jamais prises pour un autre Amiga
        0x1E62D4A5: k("ROM de la CD32", "CD32"),
        0x87746BE2: k("Extension de la CD32", "CD32"),
    ]

    static func family(_ v: Int) -> String {
        switch v {
        case 34: return "1.3"
        case 33: return "1.2"
        case ..<33: return "1.x"
        case 35...37: return "2.0"
        case 39: return "3.0"
        case 40: return "3.1"
        case 45...: return "3.x"
        default: return "\(v)"
        }
    }

    // ---------- CRC32 ----------
    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }
    static func crc32(_ d: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        d.withUnsafeBytes { (b: UnsafeRawBufferPointer) in for x in b { c = table[Int((c ^ UInt32(x)) & 0xFF)] ^ (c >> 8) } }
        return c ^ 0xFFFFFFFF
    }

    private static func info(_ path: String) -> Rom? {
        guard let b = FileManager.default.contents(atPath: path) else { return nil }
        let crc = crc32(b)
        // En-tête d'une ROM de 256 ou 512 Ko (11 11, 11 14 ou 11 16) : version et révision aux octets 12 à 15
        var v = 0, r = 0
        if b.count >= 16 && b[0] == 0x11 && [0x11, 0x14, 0x16].contains(b[1]) {
            v = Int(b[12]) << 8 | Int(b[13]); r = Int(b[14]) << 8 | Int(b[15])
            if !(30...60).contains(v) { v = 0; r = 0 }
        }
        return Rom(path: path, crc: crc, version: v, revision: r)
    }

    /// Kickstart installés (l'ancien sys/kick.rom unique est repris)
    static func list() -> [Rom] {
        let fm = FileManager.default
        let old = Paths.sys.appendingPathComponent("kick.rom").path
        if let d = fm.contents(atPath: old) { _ = add(d); try? fm.removeItem(atPath: old) }
        let names = (try? fm.contentsOfDirectory(atPath: Paths.sys.path)) ?? []
        return names.filter { $0.hasPrefix("kick-") && $0.hasSuffix(".rom") }
            .compactMap { info(Paths.sys.appendingPathComponent($0).path) }.sorted { $0.version < $1.version }
    }

    @discardableResult
    private static func add(_ d: Data) -> Rom? {
        let p = Paths.sys.appendingPathComponent(String(format: "kick-%08x.rom", crc32(d))).path
        if !FileManager.default.fileExists(atPath: p) { FileManager.default.createFile(atPath: p, contents: d) }
        return info(p)
    }

    /// Ajoute un Kickstart choisi par l'utilisateur ; renvoie la ROM, ou le motif du refus. Une ROM de la CD32 reconnue
    /// est rangée à sa place (sys/cd32.rom, cd32ext.rom).
    static func install(_ path: String) -> (Rom?, String?) {
        guard let d = FileManager.default.contents(atPath: path) else { return (nil, "fichier illisible") }
        if d.count >= 11 && String(data: d.prefix(11), encoding: .ascii) == "AMIROMTYPE1" {
            return (nil, "ROM chiffrée d'Amiga Forever : copiez la ROM déchiffrée")
        }
        guard [262144, 524288, 1048576].contains(d.count) else { return (nil, "ce fichier n'a pas la taille d'un Kickstart (256 Ko, 512 Ko ou 1 Mo)") }
        let crc = crc32(d)
        if crc == 0x1E62D4A5 || crc == 0x87746BE2 {
            let f = Paths.sys.appendingPathComponent(crc == 0x87746BE2 ? "cd32ext.rom" : "cd32.rom")
            try? d.write(to: f)
            return (Rom(path: f.path, crc: crc, version: 40, revision: 60), nil)
        }
        return (add(d), nil)
    }

    static func remove(_ r: Rom) { try? FileManager.default.removeItem(atPath: r.path) }

    /// ROM faites pour cette machine, par ordre de préférence (l'A3000 et l'A4000 se prêtent leurs ROM ; le CDTV
    /// démarre sur le Kickstart de l'Amiga 500)
    private static func groups(_ model: String) -> [Set<String>] {
        switch model {
        case "A3000": return [["A3000"], ["A4000"]]
        case "A4000": return [["A4000"], ["A3000"]]
        case "CDTV": return [["A500"]]
        default: return [[model]]
        }
    }

    /// 0 : ne convient pas ; plus c'est grand, mieux elle convient (ROM connue faite pour la machine en tête)
    private static func rank(_ r: Rom, _ model: String) -> Int {
        if r.cdtvExt { return 0 }
        if !r.models.isEmpty {
            let g = groups(model)
            for (i, set) in g.enumerated() where !r.models.isDisjoint(with: set) { return g.count - i + 1 }
            return 0
        }
        // ROM inconnue : d'après sa version. 1.x : Amiga 500 ; 2.0 : A500 et A600 ; 3.x : toutes
        let v = r.version
        let ok: Bool
        switch model {
        case "A500", "CDTV": ok = (30...37).contains(v) || v >= 39
        case "A600": ok = v == 37 || v >= 39
        case "A1200", "A3000", "A4000": ok = v >= 39
        default: ok = false
        }
        return ok ? 1 : 0
    }

    static func fits(_ r: Rom, _ model: String) -> Bool { rank(r, model) > 0 }

    /// Le meilleur Kickstart pour la machine (celui qui lui est destiné, sinon le plus récent qui convient ; le 1.3
    /// d'abord pour le CDTV, celui de la vraie console), ou nil
    static func best(_ model: String) -> Rom? {
        list().filter { fits($0, model) }.max { a, b in
            let ka = (rank(a, model), model == "CDTV" && a.version == 34 ? 1 : 0, a.version, a.revision)
            let kb = (rank(b, model), model == "CDTV" && b.version == 34 ? 1 : 0, b.version, b.revision)
            return ka < kb
        }
    }

    /// Extension du CDTV installée, ou nil
    static func cdtvExt() -> Rom? { list().first { $0.cdtvExt } }

    /// WHDLoad a besoin d'un Kickstart 3.x (il choisit lui-même la machine)
    static func hasForWhd() -> Bool {
        list().contains { !$0.cdtvExt && !$0.models.contains("CD32") && ($0.version >= 39 || !$0.models.isDisjoint(with: ["A1200", "A3000", "A4000"])) }
    }

    static var cd32Rom: Bool { FileManager.default.fileExists(atPath: Paths.sys.appendingPathComponent("cd32.rom").path) }
}
