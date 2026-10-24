import Foundation

/// Disquette vierge, formatée (DOS, système de fichiers OFS) : 880 Ko, nom de volume au choix (comme la version Android)
enum BlankDisk {
    private static let blocks = 1760

    static func adf(_ label: String) -> Data {
        var img = [UInt8](repeating: 0, count: blocks * 512)
        func put(_ off: Int, _ v: UInt32) { for i in 0..<4 { img[off + i] = UInt8((v >> (24 - 8 * UInt32(i))) & 0xFF) } }
        func get(_ off: Int) -> UInt32 { (0..<4).reduce(0) { $0 << 8 | UInt32(img[off + $1]) } }
        /// Somme de contrôle AmigaDOS : l'opposé de la somme des 128 mots longs du bloc (celui de la somme compté nul)
        func checksum(_ block: Int, _ at: Int) -> UInt32 {
            var sum: UInt32 = 0
            for i in 0..<128 where i != at { sum = sum &+ get(block + i * 4) }
            return 0 &- sum
        }
        put(0, 0x444F5300)   // « DOS\0 » : bloc de démarrage d'une disquette OFS (non démarrable)
        // Date AmigaDOS : jours depuis le 1er janvier 1978, minutes, cinquantièmes de seconde
        let cal = Calendar.current, now = Date()
        let epoch = cal.date(from: DateComponents(year: 1978, month: 1, day: 1))!
        let days = UInt32(max(0, cal.dateComponents([.day], from: epoch, to: now).day ?? 0))
        let c = cal.dateComponents([.hour, .minute, .second], from: now)
        let mins = UInt32((c.hour ?? 0) * 60 + (c.minute ?? 0)), ticks = UInt32((c.second ?? 0) * 50)
        // Bloc racine (880)
        let root = 880 * 512
        put(root, 2)                 // T_HEADER
        put(root + 3 * 4, 72)        // taille de la table de hachage
        put(root + 78 * 4, 0xFFFFFFFF)   // carte des blocs valide
        put(root + 79 * 4, 881)      // bloc de la carte
        put(root + 105 * 4, days); put(root + 106 * 4, mins); put(root + 107 * 4, ticks)
        let name = String(label.filter { $0.isASCII && $0 != ":" && $0 != "/" && ($0.asciiValue ?? 0) >= 32 }.prefix(30))
        let vol = name.isEmpty ? "Vierge" : name
        img[root + 432] = UInt8(vol.utf8.count)
        for (i, b) in vol.utf8.enumerated() { img[root + 433 + i] = b }
        put(root + 472, days); put(root + 476, mins); put(root + 480, ticks)   // modification du disque
        put(root + 484, days); put(root + 488, mins); put(root + 492, ticks)   // création
        put(root + 127 * 4, 1)       // ST_ROOT
        put(root + 5 * 4, checksum(root, 5))
        // Carte des blocs (881) : un bit par bloc à partir du bloc 2, 1 = libre ; 880 et 881 sont occupés
        let bm = 881 * 512
        for b in 2..<blocks where b != 880 && b != 881 {
            let i = b - 2, off = bm + 4 + (i / 32) * 4
            put(off, get(off) | (1 << UInt32(i % 32)))
        }
        put(bm, checksum(bm, 0))
        return Data(img)
    }
}
