# Reticule : mission de l'agent

Cadran Garmin Connect IQ (Monkey C) pour la Forerunner 165 (`fr165`, et `fr165m`), écran rond AMOLED 390 x 390.
Le code est complet mais n'a **jamais été compilé**. Ta mission : tout installer, le compiler, le tester dans le simulateur, l'installer sur la montre, de façon autonome.
L'utilisateur veut que tu fasses tout. Ne t'arrête que pour les 3 actions qu'il est seul à pouvoir faire (marquées **[UTILISATEUR]**).

Réponds en français. N'utilise jamais de tiret cadratin ni demi-cadratin dans tes messages et fichiers.

## Fichiers

- `source/ReticuleView.mc` : tout le rendu (anneau de pas, réticule, statut, météo, date + soleil, heure + secondes, 3 lignes de données, always-on).
- `source/ReticuleApp.mc` : point d'entrée.
- `manifest.xml` : `watchface`, produits fr165/fr165m, permissions SensorHistory et Positioning, minApiLevel 3.3.0.
- `docs/apercu-v3.png` : rendu attendu (reconstitué hors simulateur ; les tailles de texte réelles peuvent différer un peu).

## Étape 1 : environnement

1. `git init` si besoin, `.gitignore` avec `bin/`, `developer_key.*`, `*.prg`, `.DS_Store`.
2. Java : `java -version` ; si absent ou < 17, `brew install openjdk@17` et configure le PATH.
3. Gestionnaire de SDK en ligne de commande : `brew install lindell/connect-iq-sdk-manager-cli/connect-iq-sdk-manager`.
4. **[UTILISATEUR] Licence** : lance `connect-iq-sdk-manager agreement view`, résume-la en 3 lignes et demande à l'utilisateur s'il l'accepte. Seulement après son oui : `connect-iq-sdk-manager agreement accept`.
5. **[UTILISATEUR] Connexion Garmin** : lance `connect-iq-sdk-manager login` en interactif et laisse l'utilisateur se connecter lui-même. Ne demande jamais son mot de passe dans le chat, ne l'écris dans aucun fichier ni variable d'environnement persistante.
6. SDK : `connect-iq-sdk-manager sdk set` sur la dernière version disponible, puis `export PATH="$(connect-iq-sdk-manager sdk current-path --bin):$PATH"`.
7. Profil montre : `connect-iq-sdk-manager device download --device=fr165 --include-fonts` (et `fr165m`).
8. Clé développeur, si `developer_key.der` n'existe pas :
   `openssl genrsa -out developer_key.pem 4096 && openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt`
   Dis à l'utilisateur de sauvegarder cette clé hors du dépôt : toute future mise à jour sur le store devra être signée avec elle.

Commit.

## Étape 2 : compilation

`monkeyc -d fr165 -f monkey.jungle -o bin/Reticule.prg -y developer_key.der -w`

- Corrige toutes les erreurs **et tous les warnings**, recompile jusqu'à une sortie propre.
- Points sensibles connus : `Graphics.getVectorFont` (noms de polices sur fr165), `Weather.getSunrise/getSunset`, `Position.Location`, `Application.Storage`, vérifications `has`, typage des tableaux de classe.
- Si une API n'existe pas ou se comporte autrement sur fr165, choisis la solution la plus simple qui garde le même affichage.

Commit.

## Étape 3 : simulateur

1. Lance le simulateur (`connectiq`), puis `monkeydo bin/Reticule.prg fr165`.
2. Capture d'écran (`screencapture`). Si macOS bloque la capture, **[UTILISATEUR]** : demande-lui d'autoriser l'enregistrement d'écran pour le terminal de l'app, une seule fois.
3. Compare avec `docs/apercu-v3.png` et vérifie : aucun texte qui se chevauche ou touche l'anneau, polices lisibles, secondes sous la cible, réticule visible.
4. Teste ce que tu peux piloter (Simulation > Low Power Mode pour l'always-on, données d'activité, météo, batterie, réglage 12h). Pour tout ce qui exige de cliquer dans le simulateur et que tu ne peux pas piloter, regroupe les manipulations en une seule liste courte pour l'utilisateur.
5. Vérifie le rapport mémoire (View Memory) : le cadran doit rester largement sous la limite.
6. Lis la console du simulateur : zéro exception.

Commit après chaque correction.

## Étape 4 : installation sur la montre

1. Compile pour l'appareil (même commande, sortie `bin/Reticule.prg`).
2. Demande à l'utilisateur de brancher la montre en USB.
3. La 165 est en MTP : macOS ne la monte pas comme un disque. Utilise un outil MTP en ligne de commande si possible, sinon installe OpenMTP (`brew install --cask openmtp`) et guide l'utilisateur pour copier `Reticule.prg` dans `GARMIN/Apps`.
4. Demande-lui de sélectionner le cadran sur la montre et de te dire ce qu'il voit.

## Règles

- Ne change pas le design (couleurs, positions, données affichées) sans demander. Signale ce qui te paraît faux.
- Ne publie rien sur le Connect IQ Store.
- À la fin : un résumé court (ce qui marche, ce que tu as corrigé, ce qui reste), avec une capture du simulateur.

## Pistes pour la suite (ne pas faire sans accord)

1. Réglages dans Garmin Connect (données de chaque case, couleur d'accent, 12/24h) via `resources/settings`.
2. Compatibilité avec d'autres montres (Forerunner 265/965, Venu, Fenix) en rendant la mise en page proportionnelle à la taille d'écran.
3. Préparation de la page store (captures, description en anglais, icône).
