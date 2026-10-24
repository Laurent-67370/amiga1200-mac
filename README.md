# amiga1200-mac

Application Mac native de l'émulateur Amiga [amiga1200](https://github.com/laurent-67370/amiga1200), pour les Mac
**Apple Silicon** (M1 à M4). Elle utilise le même cœur **Amiberry (WinUAE 6)** que la version web et que
[amiga1200-android](https://github.com/laurent-67370/amiga1200-android), compilé en code ARM64 avec le **JIT** : le
68040 émulé est traduit en instructions du processeur du Mac.

> **État : en essai.** Les fonctions de la version Android y sont (Bibliothèque, Kickstart multiples, sauvegardes
> avec miniatures, reprise, filtres, MIDI, assistant…) ; l'application attend ses premiers essais sur un vrai Mac.

## Installer

1. Ouvrez la page **[Releases → dev](https://github.com/laurent-67370/amiga1200-mac/releases/tag/dev)** et téléchargez
   `amiga1200-mac.dmg`.
2. Ouvrez-le et glissez **Amiga 1200** dans **Applications**.
3. Au premier lancement, macOS bloque l'application, faute de signature d'un développeur Apple vérifié : ouvrez
   **Réglages Système → Confidentialité et sécurité**, puis **« Ouvrir quand même »**. Il ne le demande qu'une fois.

Il faut macOS 13 ou plus récent, sur un Mac Apple Silicon.

## Ce que fait l'application

- **Assistant de premier lancement** (« ✨ Assistant ») : ce que l'on veut faire (WHDLoad, disquettes, AGS, CD,
  découverte avec AROS), les Kickstart qu'il faut, les fichiers à ranger, puis le bouton qui lance ; « ? Aide » résume
  tout.
- **Écran d'accueil** : préréglages (AGS / Workbench, A1200 d'origine, Amiga 500, CD32), **quatre lecteurs** DF0: à
  DF3:, **disquette vierge** formatée (pour les sauvegardes des jeux), CD, jusqu'à **8 disques durs** (HDF, AGS
  compris), machine (**A500, A600, A1200, A3000, A4000, CD32, CDTV**), JIT, carte graphique RTG, volume SHARED:, NTSC,
  bruit des lecteurs.
- **Image** : lisse, nette (pixels francs) ou **écran cathodique** (lignes de balayage), et **pixels réguliers**
  (agrandissement en multiple entier).
- **MIDI** par CoreMIDI : l'Amiga joue sur un synthétiseur (USB, Bluetooth, réseau, application de synthé), un clavier
  MIDI joue sur l'Amiga (Bars & Pipes, Music-X, OctaMED…).
- **Mémoire et processeur** : Chip 512 Ko à 2 Mo, Slow, Fast jusqu'à 8 Mo, carte 68030 ou 68040 sans JIT (les vieux
  jeux qui veulent 512 Ko, ceux qui affichent « Error code 103 »…).
- **Plusieurs Kickstart**, reconnus à leur contenu (somme CRC et version, 3.1.4 et 3.2 compris) : chacun sert
  automatiquement à la machine qui lui convient (1.3 pour l'Amiga 500 et le CDTV, 3.1 pour l'A1200…). Sinon, la ROM
  libre **AROS** fournie. La ROM de la CD32 et l'extension du CDTV s'ajoutent de la même façon.
- **Bibliothèque** : jeux WHDLoad, disquettes, disques durs et CD déjà choisis, retrouvés d'un clic avec l'image du jeu.
  Ajout par « Ajouter des fichiers… » ou en **glissant les fichiers depuis le Finder**. Les **.zip sont analysés** :
  un disque dur ou un jeu WHDLoad zippé est extrait (Application Support/Amiga1200/Disques), une archive abîmée est
  signalée, une disquette zippée reste lue telle quelle.
- **Jeux WHDLoad** : « ▶ Jouer » pour une archive `.lha`, `.lzx` ou le dossier d'un jeu zippé, et pour un **jeu
  installé sur un .hdf** qui démarre WHDLoad tout seul (A1200, Kickstart 3.x, 8 Mo de Fast ; vos Kickstart lui sont
  donnés dans `WHDCommon:Kickstarts`). Il faut un vrai Kickstart.
- **Disques durs** : un .hdf sans table de partitions reçoit sa géométrie ; une disquette démarrée avec un Kickstart
  1.x laisse les disques durs débranchés, pour laisser sa mémoire au jeu.
- **Reprendre où j'en étais** : en quittant l'émulation, l'état est gardé ; l'accueil propose « ⏯ Reprendre » (le jeu
  WHDLoad lancé directement, ou la machine de l'accueil avec les mêmes disques).
- **Sauvegardes d'état** : quatre emplacements par jeu avec leur image et leur date (menu Amiga → Sauvegardes d'état…,
  ⌘E) ; ⌘S / ⌘L pour le premier.
- **Configurations** enregistrées sous un nom, **export et import .uae** (WinUAE, Amiberry, versions web et Android) ;
  machine, mémoire et processeur retenus pour chaque disque de démarrage.
- **Changer de Mac** : *Tout exporter…* range dans un seul `.zip` réglages, Bibliothèque, configurations, Kickstart,
  sauvegardes d'état et des jeux, disques extraits et captures ; *Importer…* sur l'autre Mac.
- **Captures d'écran** (⌘K) : l'image du jeu dans la Bibliothèque, une copie dans Images/Amiga1200 ; un jeu sans image
  en reçoit une quand on quitte.
- **Fenêtre de l'émulation** (son propre processus) : un clic capture la souris, **⌥⌘** ou **F12** la libère.
  Les touches **⌘** sont les touches Amiga ; Help (ou Inser) = Help, Début/Fin = parenthèses du pavé.
- **Manettes** (Game Controller : Xbox, PlayStation, MFi…) : la première joue sur le port joystick, la deuxième sur le
  port souris ; **touches de la manette par jeu** (X, Y, L1, R1, L2, R2, Menu… changés en touches du clavier Amiga).
- **Menu Amiga** : pause, sauvegarde et reprise rapides (⌘S, ⌘L), disquettes (⌘O, ⇧⌘O, DF2: et DF3:, éjection,
  disquette vierge ⌘N), image (⌘I : filtre suivant), **quitter le jeu WHDLoad** (⌘. : F10, ou * ou Échap au choix),
  plein écran (⌃⌘F), capture d'écran (⌘K), bruit des lecteurs, turbo (vraiment rapide, même avec le JIT), journal,
  réinitialisation (⌘R).
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
