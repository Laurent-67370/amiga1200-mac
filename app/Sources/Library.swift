import AppKit

/// Bibliothèque : les fichiers déjà choisis (jeux WHDLoad, disquettes, disques durs), retrouvés d'un clic.
/// Seul le chemin est gardé : le fichier reste où il est, lu sur place (comme la version Android).
struct LibItem {
    let path: String
    let kind: String
    let added: Double
    let used: Double
    var name: String { (path as NSString).lastPathComponent }
    var title: String { (name as NSString).deletingPathExtension }
    var exists: Bool { FileManager.default.fileExists(atPath: path) }
}

enum Library {
    static let whd = "whd", floppy = "floppy", hdf = "hdf", rom = "rom", cd = "cd"
    /// Disque dur qui démarre WHDLoad tout seul (jeu installé sur un petit .hdf) : rangé avec les jeux
    static let whdhdf = "whdhdf"
    private static let key = "bibliotheque"

    /// Type d'après le nom : un Kickstart n'est jamais rangé, il est installé comme ROM de la machine
    static func kind(_ path: String) -> String? {
        let name = (path as NSString).lastPathComponent.lowercased()
        let ext = (name as NSString).pathExtension
        if name.contains("kickstart") || ext == "rom" { return rom }
        switch ext {
        case "lha", "lzh", "lzx": return whd
        case "hdf", "hdz", "vhd": return hdf
        case "iso", "chd", "cue", "ccd", "nrg", "mds": return cd
        case "adf", "adz", "dms", "ipf", "fdi", "scp", "zip", "gz", "7z", "exe": return floppy
        default: return nil
        }
    }

    static func all() -> [LibItem] {
        let a = UserDefaults.standard.array(forKey: key) as? [[String: Any]] ?? []
        return a.compactMap { d -> LibItem? in
            guard let p = d["path"] as? String, let k = d["kind"] as? String, k != rom else { return nil }
            return LibItem(path: p, kind: k, added: d["added"] as? Double ?? 0, used: d["used"] as? Double ?? 0)
        }.sorted { max($0.used, $0.added) > max($1.used, $1.added) }
    }

    private static func save(_ items: [LibItem]) {
        UserDefaults.standard.set(items.map { ["path": $0.path, "kind": $0.kind, "added": $0.added, "used": $0.used] }, forKey: key)
    }

    /// Ajouté (ou rafraîchi) ; le type vient de l'extension, sauf s'il est donné (contenu analysé) ; faux si le type
    /// n'est pas reconnu (ou si c'est un Kickstart)
    @discardableResult
    static func add(_ path: String, kind given: String? = nil) -> Bool {
        var list = all()
        let old = list.first { $0.path == path }
        // Un élément déjà rangé garde son type (un .hdf reconnu comme jeu WHDLoad le reste)
        guard let k = given ?? old?.kind ?? kind(path), k != rom else { return false }
        list.removeAll { $0.path == path }
        list.append(LibItem(path: path, kind: k, added: old?.added ?? Date().timeIntervalSince1970, used: old?.used ?? 0))
        save(list)
        return true
    }

    static func touch(_ path: String) {
        save(all().map { $0.path == path ? LibItem(path: $0.path, kind: $0.kind, added: $0.added, used: Date().timeIntervalSince1970) : $0 })
    }

    static func remove(_ path: String) { save(all().filter { $0.path != path }) }
}

/// Captures d'écran : l'image d'un jeu dans la Bibliothèque, et une copie dans Images/Amiga1200
enum Captures {
    static var dir: URL { Paths.dir("captures") }
    static func of(_ name: String) -> URL {
        dir.appendingPathComponent(((name as NSString).deletingPathExtension as NSString).replacingOccurrences(of: "/", with: "_") + ".jpg")
    }

    /// Image affichée par l'Amiga, ou nil
    static func frame() -> CGImage? {
        var w: UInt32 = 0, h: UInt32 = 0
        guard let p = amb_frame(&w, &h), w > 0, h > 0, let data = CFDataCreate(nil, p, Int(w) * Int(h) * 4),
              let prov = CGDataProvider(data: data) else { return nil }
        return CGImage(width: Int(w), height: Int(h), bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: Int(w) * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: prov, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    static func write(_ img: CGImage, to url: URL, type: NSBitmapImageRep.FileType, maxWidth: Int? = nil) -> Bool {
        var rep = NSBitmapImageRep(cgImage: img)
        if let mw = maxWidth, img.width > mw {
            let h = img.height * mw / img.width
            guard let small = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: mw, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return false }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: small)
            NSGraphicsContext.current?.imageInterpolation = .high
            NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height)).draw(in: NSRect(x: 0, y: 0, width: mw, height: h))
            NSGraphicsContext.restoreGraphicsState()
            rep = small
        }
        guard let d = rep.representation(using: type, properties: [.compressionFactor: 0.85]) else { return false }
        return (try? d.write(to: url)) != nil
    }

    /// Image du jeu pour la Bibliothèque ; [gallery] : copie en taille réelle dans Images/Amiga1200
    static func save(name: String, gallery: Bool, onlyIfMissing: Bool = false) -> Bool {
        let f = of(name)
        if onlyIfMissing && FileManager.default.fileExists(atPath: f.path) { return false }
        guard let img = frame() else { return false }
        var ok = write(img, to: f, type: .jpeg, maxWidth: 320)
        if gallery {
            let pics = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0].appendingPathComponent("Amiga1200")
            try? FileManager.default.createDirectory(at: pics, withIntermediateDirectories: true)
            let stamp = Int(Date().timeIntervalSince1970)
            ok = write(img, to: pics.appendingPathComponent("\((name as NSString).deletingPathExtension)-\(stamp).png"), type: .png) || ok
        }
        return ok
    }
}

/// Bouton qui appelle une fermeture (lignes de la Bibliothèque, refaites à chaque mise à jour)
final class ClosureButton: NSButton {
    private var handler: (() -> Void)?
    convenience init(_ title: String, _ f: @escaping () -> Void) {
        self.init(frame: .zero)
        self.title = title; bezelStyle = .rounded; handler = f
        if title.hasPrefix("▶") { bezelColor = .systemOrange }   // boutons qui lancent un jeu
        target = self; action = #selector(fire)
    }
    @objc private func fire() { handler?() }
}

/// Fenêtre d'accueil qui accepte les fichiers glissés depuis le Finder (Bibliothèque, Kickstart)
final class DropView: NSView {
    var onDrop: (([String]) -> Void)?
    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL]) }
    required init?(coder: NSCoder) { fatalError() }
    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        let urls = s.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        onDrop?(urls.map(\.path))
        return !urls.isEmpty
    }
}
