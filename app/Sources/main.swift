import AppKit

/// Trois façons de démarrer :
///   (sans argument)               l'écran d'accueil
///   --emu <contenu> [--resume]    l'émulation (lancée par l'accueil, dans son propre processus), reprise ou non
///   --selftest <images>           essai sans fenêtre : AROS sur un A1200 avec JIT, pour la compilation automatique
let args = CommandLine.arguments

if let i = args.firstIndex(of: "--selftest") {
    exit(SelfTest.run(frames: i + 1 < args.count ? Int(args[i + 1]) ?? 600 : 600))
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
if let i = args.firstIndex(of: "--emu"), i + 1 < args.count {
    let delegate = EmuDelegate(content: args[i + 1], resume: args.contains("--resume"))
    app.delegate = delegate
    app.run()
} else {
    let delegate = HomeDelegate()
    app.delegate = delegate
    app.run()
}

/// Essai sans fenêtre ni son : le cœur démarre AROS sur un A1200 (68040 avec JIT, RTG), tourne sans frein,
/// et l'on vérifie qu'il calcule des images, qu'elles ne sont pas noires et que le JIT est actif
enum SelfTest {
    static func run(frames: Int) -> Int32 {
        let s = Settings.shared
        s.model = "A1200"; s.jit = true; s.rtg = true; s.floppySound = false
        Paths.installResources()
        amb_mute_audio(1)
        amb_set_log(Paths.log.path)
        let cfg = Config.write(s, arosOnly: true)
        guard Core.start(cfg.path) else { print("ÉCHEC : le fil de l'émulation n'a pas démarré"); return 1 }
        let t0 = Date()
        while amb_state() == 1 && Date().timeIntervalSince(t0) < 60 { usleep(50_000) }
        guard amb_state() == 2 else { print("ÉCHEC : le cœur a refusé la configuration (état \(amb_state()))"); return 1 }
        amb_turbo(1)
        let t1 = Date()
        _ = amb_frames(); _ = amb_busy_us()
        var done = 0
        while done < frames && Date().timeIntervalSince(t1) < 180 { usleep(100_000); done += Int(amb_frames()) }
        let secs = Date().timeIntervalSince(t1)
        var w: UInt32 = 0, h: UInt32 = 0
        var lit = 0
        if let p = amb_frame(&w, &h), w > 0, h > 0 {
            for i in stride(from: 0, to: Int(w) * Int(h), by: 7) where p[i * 4] > 16 || p[i * 4 + 1] > 16 || p[i * 4 + 2] > 16 { lit += 1 }
        }
        amb_stop()
        usleep(200_000)
        let log = (try? String(contentsOf: Paths.log, encoding: .utf8)) ?? ""
        let jit = log.contains("JIT=CPU/FPU") || log.contains("JIT=CPU")
        print(String(format: "Essai : %ld images en %.1f s (%.0f images/s sans frein), image %ux%u, %ld points allumés, JIT %@",
                     done, secs, Double(done) / max(secs, 0.001), w, h, lit, jit ? "actif" : "ABSENT"))
        if let line = log.split(separator: "\n").first(where: { $0.contains("JIT=") }) { print("Cœur : \(line)") }
        guard done >= frames else { print("ÉCHEC : trop peu d'images"); return 1 }
        guard w > 0 && h > 0 && lit > 0 else { print("ÉCHEC : image vide"); return 1 }
        guard jit else { print("ÉCHEC : JIT inactif"); return 1 }
        print("OK")
        return 0
    }
}
