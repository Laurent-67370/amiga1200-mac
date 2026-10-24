import Foundation

/// Archives .zip : un disque dur (.hdf) ou un jeu WHDLoad (.lha) zippé ne se lit pas comme une disquette. Ils sont
/// extraits (Application Support/Amiga1200/Disques) et rangés selon ce qu'ils sont ; un .hdf qui démarre WHDLoad tout
/// seul devient un jeu (▶ Jouer), le dossier d'un jeu WHDLoad zippé se lance comme une .lha. Les disquettes zippées
/// restent lues telles quelles. Comme la version Android, avec l'outil unzip de macOS.
enum ZipImport {
    struct Found { let path: String; let kind: String }
    struct Result { var found: [Found] = []; var problem: String?; var whdArchive = false }

    static var dir: URL { Paths.dir("Disques") }

    @discardableResult
    private static func unzip(_ args: [String], to file: String? = nil) -> (Int32, Data) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = args
        let out = Pipe()
        if let file {
            FileManager.default.createFile(atPath: file, contents: nil)
            p.standardOutput = FileHandle(forWritingAtPath: file)
        } else { p.standardOutput = out }
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return (-1, Data()) }
        let data = file == nil ? out.fileHandleForReading.readDataToEndOfFile() : Data()
        p.waitUntilExit()
        return (p.terminationStatus, data)
    }

    /// Nom d'un fichier de l'archive pour unzip, qui lit ses arguments comme des motifs
    private static func pattern(_ n: String) -> String {
        var s = ""
        for c in n { if "[]*?\\".contains(c) { s.append("\\") }; s.append(c) }
        return s
    }

    /// Analyse et extraction ; found vide, problem nil et whdArchive faux : une disquette zippée, à garder telle quelle
    static func inspect(_ zip: String) -> Result {
        let name = (zip as NSString).lastPathComponent
        var r = Result()
        // Archive complète et sans erreur (sommes CRC vérifiées) ?
        if unzip(["-tqq", zip]).0 != 0 {
            r.problem = "\(name) est incomplet ou abîmé (téléchargement interrompu ?) : retéléchargez-le."
            return r
        }
        let names = String(data: unzip(["-Z1", zip]).1, encoding: .utf8)?.split(separator: "\n").map(String.init) ?? []
        for n in names where !n.hasSuffix("/") {
            let base = (n as NSString).lastPathComponent, ext = (base as NSString).pathExtension.lowercased()
            let kind: String
            switch ext {
            case "hdf", "hdz": kind = Library.hdf
            case "lha", "lzh": kind = Library.whd
            default: continue
            }
            let dest = dir.appendingPathComponent(base).path
            let part = dest + ".part"
            if unzip(["-p", zip, pattern(n)], to: part).0 != 0 {
                try? FileManager.default.removeItem(atPath: part)
                r.problem = "\(name) : extraction de \(base) impossible."
                continue
            }
            try? FileManager.default.removeItem(atPath: dest)
            try? FileManager.default.moveItem(atPath: part, toPath: dest)
            r.found.append(Found(path: dest, kind: kind == Library.hdf && bootsWhdload(dest) ? Library.whdhdf : kind))
        }
        r.whdArchive = r.found.isEmpty && names.contains { $0.lowercased().hasSuffix(".slave") }
        return r
    }

    /// Disque qui démarre WHDLoad de lui-même : S:startup-sequence lance un .slave (« WHDLoad Jeu.Slave Preload »).
    /// Les gros disques (AGS…) ne sont pas lus.
    static func bootsWhdload(_ path: String) -> Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        guard size > 0 && size <= 64 << 20, let h = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? h.close() }
        let re = try! NSRegularExpression(pattern: "WHDLoad[^\\n]{0,80}\\.slave", options: [.caseInsensitive])
        var tail = ""
        while true {
            let d = h.readData(ofLength: 1 << 20)
            if d.isEmpty { break }
            let text = tail + (String(data: d, encoding: .isoLatin1) ?? "")
            if re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil { return true }
            tail = String(text.suffix(128))
        }
        return false
    }
}
