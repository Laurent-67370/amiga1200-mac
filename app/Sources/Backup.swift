import Foundation

/// Changer de Mac : réglages, Bibliothèque, configurations, Kickstart, sauvegardes d'état, sauvegardes des jeux
/// (WHDLoad, SHARED:), disques extraits des archives et captures dans un seul fichier .zip (outils zip et unzip de
/// macOS). Les jeux et disques rangés ailleurs n'y sont pas : sur l'autre Mac, ajoutez-les à la Bibliothèque, les
/// réglages qui les citent les retrouvent par leur nom.
enum Backup {
    private static let prefsName = "reglages.plist"
    private static var domain: String { Bundle.main.bundleIdentifier ?? "io.github.laurent67370.amiga1200" }

    @discardableResult
    private static func run(_ tool: String, _ args: [String], in dir: URL? = nil) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        if let dir { p.currentDirectoryURL = dir }
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    static func export(to url: URL) -> String {
        let fm = FileManager.default
        var prefs = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
        prefs["sauvegarde.dossier"] = Paths.support.path   // pour réécrire les chemins sur l'autre Mac
        guard let data = try? PropertyListSerialization.data(fromPropertyList: prefs, format: .xml, options: 0) else { return "Export impossible" }
        let plist = Paths.support.appendingPathComponent(prefsName)
        try? data.write(to: plist)
        defer { try? fm.removeItem(at: plist) }
        try? fm.removeItem(at: url)
        // Fichiers recopiés depuis l'application (AROS, WHDBoot hors sauvegardes des jeux) : inutiles dans la sauvegarde
        let have = ["sys", "save", "etats", "captures", "Disques"].filter { fm.fileExists(atPath: Paths.support.appendingPathComponent($0).path) }
        guard run("/usr/bin/zip", ["-r", "-q", "-y", url.path, prefsName] + have + ["-x", "sys/aros-*", "save/WHDBoot/*"], in: Paths.support) == 0 else { return "Export impossible" }
        if fm.fileExists(atPath: Paths.save.appendingPathComponent("WHDBoot/save-data").path) {
            run("/usr/bin/zip", ["-r", "-q", url.path, "save/WHDBoot/save-data"], in: Paths.support)
        }
        let docs = Paths.shared.deletingLastPathComponent()
        run("/usr/bin/zip", ["-r", "-q", url.path, "SHARED"], in: docs)
        let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        return "Sauvegarde exportée (\(size / (1 << 20)) Mo). Elle contient vos Kickstart : gardez-la pour vous."
    }

    static func `import`(from url: URL) -> String {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("amiga1200-import-\(getpid())")
        try? fm.removeItem(at: tmp)
        defer { try? fm.removeItem(at: tmp) }
        guard run("/usr/bin/unzip", ["-o", "-qq", url.path, "-d", tmp.path]) == 0,
              let data = fm.contents(atPath: tmp.appendingPathComponent(prefsName).path),
              var prefs = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
        else { return "Ce fichier n'est pas une sauvegarde d'Amiga 1200 (ou il est abîmé)." }
        // Fichiers : ajoutés ou remplacés
        var files = 0
        func merge(_ src: URL, _ dst: URL) {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: src.path, isDirectory: &isDir) else { return }
            if isDir.boolValue {
                try? fm.createDirectory(at: dst, withIntermediateDirectories: true)
                for n in (try? fm.contentsOfDirectory(atPath: src.path)) ?? [] { merge(src.appendingPathComponent(n), dst.appendingPathComponent(n)) }
            } else { try? fm.removeItem(at: dst); if (try? fm.copyItem(at: src, to: dst)) != nil { files += 1 } }
        }
        for d in ["sys", "save", "etats", "captures", "Disques"] { merge(tmp.appendingPathComponent(d), Paths.support.appendingPathComponent(d)) }
        merge(tmp.appendingPathComponent("SHARED"), Paths.shared)
        // Réglages : remplacés ; les chemins de l'ancien dossier de l'application pointent vers celui de ce Mac
        let old = prefs.removeValue(forKey: "sauvegarde.dossier") as? String
        func fix(_ v: Any) -> Any {
            if let s = v as? String, let o = old, s.hasPrefix(o) { return Paths.support.path + String(s.dropFirst(o.count)) }
            if let a = v as? [Any] { return a.map(fix) }
            if let d = v as? [String: Any] { return d.mapValues(fix) }
            return v
        }
        let d = UserDefaults.standard
        for (k, _) in d.persistentDomain(forName: domain) ?? [:] { d.removeObject(forKey: k) }
        for (k, v) in prefs { d.set(fix(v), forKey: k) }
        let lost = Library.all().filter { !$0.exists }.map(\.name)
        return "Sauvegarde importée : réglages et \(files) fichier\(files > 1 ? "s" : "")." +
            (lost.isEmpty ? "" : " Disques à rajouter à la Bibliothèque (introuvables sur ce Mac) : " + lost.joined(separator: ", "))
    }
}
