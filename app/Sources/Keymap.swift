import Foundation

/// Touches du Mac (codes physiques, donc indépendants de la disposition AZERTY ou QWERTY) → codes RETROK du clavier
/// libretro, comme la version web et la version Android. Les touches absentes du Mac suivent la version Android :
/// Help (ou Inser d'un clavier de PC) = Help, ⌘ et Page préc./suiv. = touches Amiga, Début/Fin = parenthèses du pavé.
enum Keymap {
    static let map: [UInt16: UInt32] = {
        var m: [UInt16: UInt32] = [:]
        let letters: [(UInt16, Character)] = [
            (0, "a"), (1, "s"), (2, "d"), (3, "f"), (4, "h"), (5, "g"), (6, "z"), (7, "x"), (8, "c"), (9, "v"),
            (11, "b"), (12, "q"), (13, "w"), (14, "e"), (15, "r"), (16, "y"), (17, "t"), (31, "o"), (32, "u"),
            (34, "i"), (35, "p"), (37, "l"), (38, "j"), (40, "k"), (45, "n"), (46, "m"),
        ]
        for (k, c) in letters { m[k] = UInt32(c.asciiValue!) }
        let digits: [(UInt16, UInt32)] = [(29, 48), (18, 49), (19, 50), (20, 51), (21, 52), (23, 53), (22, 54), (26, 55), (28, 56), (25, 57)]
        for (k, r) in digits { m[k] = r }
        // Ponctuation : = - ] [ ' ; \ , / . `
        let punct: [(UInt16, UInt32)] = [(24, 61), (27, 45), (30, 93), (33, 91), (39, 39), (41, 59), (42, 92), (43, 44), (44, 47), (47, 46), (50, 96)]
        for (k, r) in punct { m[k] = r }
        m[10] = 60          // touche < > des claviers ISO (RETROK_LESS)
        m[36] = 13; m[48] = 9; m[49] = 32; m[51] = 8; m[53] = 27; m[117] = 127   // Retour, Tab, Espace, ⌫, Échap, Suppr
        // F1 à F10
        let fkeys: [(UInt16, UInt32)] = [(122, 282), (120, 283), (99, 284), (118, 285), (96, 286), (97, 287), (98, 288), (100, 289), (101, 290), (109, 291)]
        for (k, r) in fkeys { m[k] = r }
        m[126] = 273; m[125] = 274; m[124] = 275; m[123] = 276       // flèches
        // Pavé numérique
        let pad: [(UInt16, UInt32)] = [(82, 256), (83, 257), (84, 258), (85, 259), (86, 260), (87, 261), (88, 262), (89, 263), (91, 264), (92, 265)]
        for (k, r) in pad { m[k] = r }
        m[65] = 266; m[75] = 267; m[67] = 268; m[78] = 269; m[69] = 270; m[76] = 271; m[81] = 272
        // Touches propres à l'Amiga
        m[114] = 281                 // Help (Inser d'un clavier de PC)
        m[55] = 311; m[54] = 312     // ⌘ gauche et droit = Amiga gauche et droite
        m[116] = 311; m[121] = 312   // Page préc./suiv. = touches Amiga
        m[115] = 295; m[119] = 296   // Début/Fin = parenthèses du pavé
        // Modificateurs
        m[56] = 304; m[60] = 303; m[59] = 306; m[62] = 305; m[58] = 308; m[61] = 307; m[57] = 301
        return m
    }()

    static func retrok(_ keyCode: UInt16) -> UInt32? { map[keyCode] }
    static let modifiers: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62]
}
