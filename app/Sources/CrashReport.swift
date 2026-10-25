import AppKit

/// Plantage du processus de l'émulation (comme la version Android) : il note son numéro de processus en démarrant et
/// l'efface en quittant normalement. Une marque restée alors que le processus n'existe plus, c'est un arrêt brutal :
/// l'accueil prépare un rapport (fin du journal, rapport de plantage de macOS) et propose de le transmettre.
enum CrashReport {
    private static var marker: URL { Paths.support.appendingPathComponent(".emulation") }
    static var file: URL { Paths.support.appendingPathComponent("plantage.txt") }

    /// Processus de l'émulation : au démarrage et à la sortie normale
    static func started() { try? "\(getpid())".write(to: marker, atomically: true, encoding: .utf8) }
    static func ended() {
        if (try? String(contentsOf: marker, encoding: .utf8)) == "\(getpid())" { try? FileManager.default.removeItem(at: marker) }
    }

    /// Accueil : au lancement et à la fin de chaque émulation
    static func check(_ show: @escaping (String, String) -> Void) {
        let fm = FileManager.default
        guard let pidText = try? String(contentsOf: marker, encoding: .utf8), let pid = Int32(pidText) else { return }
        if kill(pid, 0) == 0 { return }   // encore en marche
        let since = (try? fm.attributesOfItem(atPath: marker.path)[.modificationDate] as? Date) ?? .distantPast
        try? fm.removeItem(at: marker)
        // macOS écrit son rapport (.ips) quelques secondes après le plantage : on l'attend un peu, à part
        DispatchQueue.global(qos: .utility).async {
            let dir = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/DiagnosticReports")
            var ips: URL?
            for _ in 0..<20 {
                ips = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
                    .filter { $0.lastPathComponent.hasPrefix("Amiga1200") }
                    .filter { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) >= since }
                    .max { $0.lastPathComponent < $1.lastPathComponent }
                if ips != nil { break }
                Thread.sleep(forTimeInterval: 0.5)
            }
            let fmt = DateFormatter(); fmt.locale = Locale(identifier: "fr_FR"); fmt.dateFormat = "dd/MM/yyyy HH:mm:ss"
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
            var r = "Plantage de l'émulation le \(fmt.string(from: Date())) (amiga1200-mac \(version) (\(build)), macOS \(ProcessInfo.processInfo.operatingSystemVersionString))\n\n"
            let log = (try? String(contentsOf: Paths.log, encoding: .utf8))?.components(separatedBy: "\n").suffix(150) ?? []
            r += "— Fin du journal de la séance —\n" + log.joined(separator: "\n") + "\n\n"
            if let ips, let text = try? String(contentsOf: ips, encoding: .utf8) {
                r += "— Rapport de macOS (\(ips.lastPathComponent)) —\n" + String(text.prefix(60_000))
            } else {
                r += "(pas de rapport de macOS : l'émulation a peut-être été arrêtée de force)"
            }
            try? r.write(to: file, atomically: true, encoding: .utf8)
            DispatchQueue.main.async { show(r, fmt.string(from: Date())) }
        }
    }

    /// Fenêtre proposée par l'accueil
    static func present(_ report: String, _ date: String) {
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = "L'émulation s'est arrêtée brutalement"
        a.informativeText = "Un rapport a été préparé (\(date)) : la fin du journal et le rapport de plantage de macOS. Transmettez-le pour aider à corriger le problème."
        a.addButton(withTitle: "Signaler sur GitHub…")
        a.addButton(withTitle: "Copier le rapport")
        a.addButton(withTitle: "Ouvrir le rapport")
        a.addButton(withTitle: "Fermer")
        func copy() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(report, forType: .string) }
        switch a.runModal() {
        case .alertFirstButtonReturn:
            // Le rapport est trop long pour l'adresse : il est copié, à coller dans le signalement
            copy()
            var c = URLComponents(string: "https://github.com/laurent-67370/amiga1200-mac/issues/new")!
            c.queryItems = [URLQueryItem(name: "title", value: "Plantage de l'émulation (\(date))"),
                            URLQueryItem(name: "body", value: "Ce que je faisais :\n\n\n(Le rapport est copié : collez-le ici avec ⌘V.)\n")]
            if let u = c.url { NSWorkspace.shared.open(u) }
        case .alertSecondButtonReturn: copy()
        case .alertThirdButtonReturn: NSWorkspace.shared.open(file)
        default: break
        }
    }
}
