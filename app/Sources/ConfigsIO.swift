import Foundation

/// Configuration au format WinUAE (.uae) : export lisible par WinUAE, Amiberry et les versions web et Android (les
/// disques y gardent leur chemin, qui donne aussi leur nom de fichier), import qui reprend la machine et retrouve les
/// disques à leur place, sinon par leur nom dans la Bibliothèque.
enum ConfigsIO {
    static func export(_ s: Settings, to url: URL) -> Bool {
        let lines = (try? String(contentsOf: Config.write(s), encoding: .utf8)) ?? ""
        let text = "; Configuration exportée par amiga1200-mac\n" + lines
        return (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil
    }

    /// Import : machine (modèle, JIT, RTG, NTSC, mémoire) et disques ; renvoie le compte rendu
    static func `import`(_ s: Settings, from url: URL) -> String {
        guard let text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) else { return "Lecture impossible" }
        var kv: [(String, String)] = []
        for raw in text.components(separatedBy: .newlines) {
            let l = raw.trimmingCharacters(in: .whitespaces)
            guard !l.isEmpty, !l.hasPrefix(";"), let eq = l.firstIndex(of: "=") else { continue }
            kv.append((String(l[..<eq]).trimmingCharacters(in: .whitespaces), String(l[l.index(after: eq)...]).trimmingCharacters(in: .whitespaces)))
        }
        func value(_ k: String) -> String? { kv.first { $0.0 == k }?.1 }
        let lib = Library.all()
        var missing: [String] = []
        /// Le disque à son chemin, sinon l'élément de même nom de la Bibliothèque
        func find(_ p: String) -> String? {
            let path = p.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if FileManager.default.fileExists(atPath: path) { return path }
            let n = path.components(separatedBy: CharacterSet(charactersIn: "/\\")).last ?? path
            if let it = lib.first(where: { $0.name.lowercased() == n.lowercased() }) { return it.path }
            missing.append(n); return nil
        }
        if let q = value("quickstart")?.components(separatedBy: ",").first?.uppercased() {
            if ["A500", "A600", "A1200", "A3000", "A4000", "CD32", "CDTV"].contains(q) { s.model = q }
            else if ["A1000", "A2000", "A500+"].contains(q) { s.model = "A500" } else if q == "A4000T" { s.model = "A4000" }
        }
        if let c = value("cachesize") { s.jit = (Int(c) ?? 0) > 0 }
        s.rtg = kv.contains { $0.0 == "gfxcard_size" && (Int($0.1) ?? 0) > 0 }
        if let n = value("ntsc") { s.ntsc = n.lowercased() == "true" }
        if let c = value("chipmem_size"), let v = Int(c) { s.chip = v }
        if let c = value("bogomem_size"), let v = Int(c) { s.slow = v }
        if !s.jit, let c = value("fastmem_size"), let v = Int(c) { s.fast = [0, 2, 4, 8].last { $0 <= v } ?? 0 }
        s.df0 = value("floppy0").flatMap(find) ?? ""
        s.df1 = value("floppy1").flatMap(find) ?? ""
        s.hds = kv.filter { $0.0 == "hardfile2" || $0.0 == "hardfile" }.compactMap { (_, v) -> String? in
            let f = v.components(separatedBy: ",")
            guard f.count > 1 else { return nil }
            let p = f[1].contains(":") ? String(f[1][f[1].index(after: f[1].firstIndex(of: ":")!)...]) : f[1]
            return find(p)
        }
        if let c = value("cdimage0") { s.cd = find(c.components(separatedBy: ",image").first ?? c) ?? "" }
        return missing.isEmpty ? "Configuration importée" :
            "Configuration importée. Introuvables (ajoutez-les à la Bibliothèque puis importez à nouveau) : " + missing.joined(separator: ", ")
    }
}
