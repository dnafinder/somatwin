# Somatwin (Flutter, Android)

Gemello digitale wireframe da misure antropometriche, indici e rischio cardiovascolare.
Base: referto CARDIOMET e script MATLAB (BMIfun, BSAfun, cardiofun, GrantIndex, BMR, BEE...).

## Avvio
    flutter create --platforms=android .   # genera la cartella android/ (non toccare lib/, assets/, pubspec.yaml)
    flutter pub get
    flutter test
    flutter run

## Struttura
- lib/core: indici (indices.dart), tabelle ABSI, modelli. Dart puro.
- lib/twin: modello corporeo (sezioni ellittiche, volume = peso/1,010) e vista 3D su Canvas.
- lib/ui: storico, form, risultati (Twin / Indici / Confronto).
- test: valori di riferimento dal port Python che riproduce il referto.

## Build senza Flutter in locale (GitHub Actions)
1. Crea un repository (anche privato) e carica tutto il contenuto di questa cartella, inclusa .github/.
2. Scheda Actions, workflow "Build APK", Run workflow (parte anche a ogni push su main).
3. A fine esecuzione scarica l'artefatto "somatwin-apk", estrai app-release.apk.
4. Copialo sul telefono e installalo (consenti le origini sconosciute). L'APK release e' firmato con la chiave di debug: va bene per provarlo, non per il Play Store.
Il workflow esegue anche flutter test: se un test fallisce, il build si ferma e il log dice quale.
