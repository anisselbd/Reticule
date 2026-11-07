# Reticule

Cadran Connect IQ pour Garmin Forerunner 165 / 165 Music.

## Compiler et installer

1. Installer le Connect IQ SDK avec le SDK Manager, puis l'extension Monkey C dans VS Code.
2. Lancer `Monkey C: Generate a Developer Key` si besoin.
3. Ouvrir ce dossier dans VS Code et lancer `Monkey C: Run` pour tester dans le simulateur.
4. Lancer `Monkey C: Build for Device`, choisir `fr165`, puis copier le `.prg` dans `GARMIN/Apps` sur la montre en USB.

## Lecture du cadran

De haut en bas :

- Bluetooth (blanc si le téléphone est connecté), notifications en attente, lune si Ne pas déranger est actif.
- Météo : ciel, température, min/max du jour, risque de pluie. Lune la nuit.
- Date, puis prochain lever ou coucher du soleil.
- Heure, avec les secondes sous la cible (visibles quand l'écran est actif).
- Fréquence cardiaque, pas, distance du jour.
- Body Battery, calories, minutes intensives de la semaine (amarante une fois l'objectif atteint).
- Batterie en % et autonomie estimée en jours (ou en heures sous 1 jour).
- Anneau de 60 graduations : objectif de pas du jour.
- Always-on : chiffres fins déplacés chaque minute.

Le lever/coucher du soleil utilise la position de la météo ou le dernier GPS ; la dernière position valable est gardée en mémoire.
