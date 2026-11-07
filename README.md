# Atelier — mini-Photoshop pour iPad

Une app iPad (SwiftUI + UIKit) volontairement simple pour : importer une photo, la découper en morceaux, peindre dessus, boucher des trous (content-aware), recadrer, appliquer de la netteté, puis exporter directement dans Photos.

## Fonctions

| Outil | Ce qu'il fait |
|---|---|
| **Pinceau** | Rond, taille / opacité / dureté, pression Apple Pencil → taille. L'opacité est plafonnée par trait (pas d'accumulation). |
| **Gomme** | Même moteur, efface la transparence. |
| **Pipette** | Glisser sur l'image → couleur en direct, puis retour au pinceau. |
| **Sélection** | **Points** (segments droits), **Courbe** (points lissés), **Lasso**, **Rectangle**, **Ellipse**. Modes Nouvelle / Ajouter / Soustraire. Les points se déplacent au doigt ; double-tap sur un point = angle ↔ courbe ; tap sur le 1er point = fermer. |
| Actions sur sélection | Remplissage intelligent (content-aware), Découper vers un nouveau calque, Copier vers un calque, Effacer, Remplir, Recadrer à la sélection, Inverser. Le pinceau et la gomme sont limités à la sélection. |
| **Déplacer** | Glisse le calque actif (pratique après une découpe). |
| **Recadrer** | Cadre avec poignées, formats Libre / Original / 1:1 / 4:3 / 3:2 / 16:9. |
| **Netteté** | Unsharp mask (rayon + intensité) avec aperçu en direct, limité à la sélection s'il y en a une. |
| **Calques** | Ajouter (vide ou photo), dupliquer, fusionner vers le bas, monter/descendre, visibilité, opacité, renommer (appui long). |
| **Export** | Photos en JPEG ou PNG (transparence), calque actif seul ou chaque calque séparément (rognés à leur contenu), copier, partager. |

**Gestes** : pincer = zoom, deux doigts = déplacer la vue, tap à 2 doigts = annuler, tap à 3 doigts = rétablir, double-tap Apple Pencil = pinceau ↔ gomme. Le bouton ✋ de la barre du haut réserve le dessin à l'Apple Pencil (le doigt navigue).

## Obtenir le .ipa via GitHub (sans compte développeur)

1. Crée un dépôt GitHub (privé ou public) et pousse ce dossier sur la branche `main`.
2. L'action **Build IPA** se lance toute seule (onglet *Actions*). Elle génère le projet Xcode avec XcodeGen, compile en Release sans signature et emballe `Atelier.ipa`.
3. Télécharge l'artefact **Atelier-ipa** en bas de la page du run (c'est un zip qui contient le `.ipa`).
4. Pour une release : `git tag v1.0 && git push --tags` → le `.ipa` est attaché à la release GitHub.

### Installer sur l'iPad

Le `.ipa` n'est pas signé : il faut le signer à l'installation avec ton Apple ID gratuit.

- **Sideloadly** (Mac/PC) ou **AltStore** : glisse le `.ipa`, connecte-toi avec ton Apple ID → installé.
  Avec un Apple ID gratuit l'app expire au bout de **7 jours** (AltStore peut la rafraîchir automatiquement).
- Sur l'iPad : *Réglages → Général → VPN et gestion de l'appareil* → faire confiance au certificat.
- iPadOS 16+ : activer *Réglages → Confidentialité et sécurité → Mode développeur*.

## Structure

```
project.yml                     # XcodeGen (iPad, iOS 16+)
.github/workflows/build-ipa.yml # build non signé + .ipa
Atelier/
  App/          point d'entrée
  Model/        EditorModel (état, undo, opérations), PaintLayer (bitmap), types
  Canvas/       CanvasView (UIKit : zoom, pinceau, sélection, recadrage), overlay
  Processing/   Inpainter (PatchMatch multi-échelle), ImageOps (netteté, export)
  UI/           barres, palette, panneau calques
```

### Notes techniques

- Les images importées sont limitées à 4096 px de côté (mémoire et fluidité).
- Le remplissage intelligent est un PatchMatch multi-échelle (vote EM, patchs 7×7) calculé sur une zone autour de la sélection ; prévoir quelques secondes pour les grosses zones. Il marche le mieux sur des textures (ciel, herbe, mur, sable).
- L'historique d'annulation garde ~700 Mo de snapshots (5 à 30 étapes selon la taille de l'image).
