# amiga1200-mac

Application Mac native de l'émulateur Amiga [amiga1200](https://github.com/laurent-67370/amiga1200), pour les Mac
**Apple Silicon** (M1 à M4). Elle utilise le même cœur **Amiberry (WinUAE 6)** que la version web et que
[amiga1200-android](https://github.com/laurent-67370/amiga1200-android), compilé en code ARM64 avec le **JIT** : le
68040 émulé est traduit en instructions du processeur du Mac.

> **État : prototype.** Il vérifie que le cœur tourne sur Mac avec le JIT, avec l'image, le son, le clavier, la
> souris et les manettes. Les fonctions de la version Android (Bibliothèque, sauvegardes avec miniatures, filtres…)
> viendront ensuite, bloc par bloc.

## Installer

1. Ouvrez la page **[Releases → dev](https://github.com/laurent-67370/amiga1200-mac/releases/tag/dev)** et téléchargez
   `amiga1200-mac.dmg`.
2. Ouvrez-le et glissez **Amiga 1200** dans **Applications**.
3. Au premier lancement, macOS bloque l'application, faute de signature d'un développeur Apple vérifié : ouvrez
   **Réglages Système → Confidentialité et sécurité**, puis **« Ouvrir quand même »**. Il ne le demande qu'une fois.

Il faut macOS 13 ou plus récent, sur un Mac Apple Silicon.

## Ce que fait le prototype

- **Écran d'accueil** : préréglages (AGS / Workbench, A1200 d'origine, Amiga 500), Kickstart (le vôtre, sinon la ROM
  libre **AROS** fournie), disquettes DF0: et DF1:, jusqu'à **8 disques durs** (HDF, AGS compris), machine (A500, A600,
  A1200, A4000), JIT, carte graphique RTG, volume SHARED:, NTSC, bruit des lecteurs, image nette ou lisse.
- **Jeux WHDLoad** : une archive `.lha` mise dans DF0: se lance seule (il faut un vrai Kickstart).
- **Fenêtre de l'émulation** (son propre processus) : un clic capture la souris, **⌥⌘** ou **F12** la libère.
  Les touches **⌘** sont les touches Amiga ; Help (ou Inser) = Help, Début/Fin = parenthèses du pavé.
- **Manettes** (Game Controller : Xbox, PlayStation, MFi…) : la première joue sur le port joystick, la deuxième sur le
  port souris.
- **Menu Amiga** : pause, sauvegarde et reprise rapides (⌘S, ⌘L), disquettes (⌘O), image nette ou lisse (⌘I), plein
  écran (⌃⌘F), bruit des lecteurs, turbo, journal, réinitialisation (⌘R).
- **Son** par Core Audio, l'émulation cadencée par le son (comme la version Android) ; vitesse affichée dans le titre.

Dossiers : réglages, ROM et sauvegardes dans `~/Library/Application Support/Amiga1200` ; volume SHARED: dans
`~/Documents/Amiga1200/SHARED`.

## Comment c'est construit

| Élément | Origine |
|---|---|
| Cœur Amiberry 8.3 (WinUAE 6) | `BlitterStudio/amiberry`, même version que la version web, Makefile libretro `platform=osx` (JIT ARM64 compris) |
| Correctifs du cœur | `native/patches/` : ceux de la version Android (touches, manette CD32, mémoire RTG des sauvegardes d'état, cadence laissée au frontal) |
| Frontal libretro | `amiga1200/wasm/frontend.c` (sous-module **amiga1200**), compilé tel quel ; `native/compat/` remplace les fonctions d'Emscripten qu'il utilise |
| Pont | `native/bridge.c` : fil de l'émulation cadencé par le son, Core Audio, journal du cœur, fonctions appelées depuis Swift |
| Application | `app/Sources` : Swift (AppKit, Core Animation, Game Controller), sans bibliothèque externe |

La compilation est faite par GitHub Actions sur un Mac Apple Silicon (`.github/workflows/mac.yml`) : cœur, application,
puis un **essai réel** (`--selftest` : AROS démarre sur un A1200 avec JIT, sans fenêtre ; l'essai vérifie que des
images sont calculées, qu'elles ne sont pas noires et que le JIT est actif). Depuis `main`, l'image disque est publiée
dans la release `dev`.

Pour compiler sur un Mac (outils en ligne de commande de Xcode installés) :

```sh
git clone --recurse-submodules https://github.com/laurent-67370/amiga1200-mac.git
cd amiga1200-mac
native/build-core.sh
scripts/build-app.sh
open "build/Amiga 1200.app"
```

## Licences

GPL v3, comme Amiberry et la version web. AROS est sous licence publique AROS. Les Kickstart d'Amiga ne sont pas
fournis : utilisez les vôtres.
