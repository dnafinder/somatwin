# Somatwin

App Flutter (Android e web) che costruisce un gemello digitale da misure antropometriche e ne ricava indici e stime di rischio cardiovascolare. Il calcolo riproduce gli script MATLAB del referto CARDIOMET (MEDyLAB).

**Gli esiti sono stime informative, non una diagnosi.** L'interpretazione clinica compete al medico.

- Web: https://dnafinder.github.io/somatwin/
- APK: ultima build nella sezione [Releases](../../releases) (`build-N`)

## Come si usa

1. **Registro.** Si aggiunge un soggetto con cognome, nome, sesso e data di nascita (solo adulti, almeno 18 anni). Questi dati non cambiano: valgono per tutte le misure del soggetto e si correggono dalla matita nell'elenco.
2. **Misure.** Dentro un soggetto si inserisce una nuova misura: peso, altezza, circonferenze di vita, fianchi, polso, collo e polpaccio, pressione sistolica e diastolica, frequenza cardiaca. L'anamnesi (fumo, genitori ipertesi, terapia antipertensiva) è facoltativa e serve solo al rischio di ipertensione.
3. **Risultati.** Quattro schede: *Twin*, *Circolo*, *Indici* e *Confronto* con la misura precedente dello stesso soggetto.
4. **Eliminazione.** Si può cancellare una singola misura oppure un intero soggetto con tutte le sue misure, sempre con conferma.

I dati restano sul dispositivo (archivio locale del browser o dell'app). Non c'è un server.

## Cosa mostra

**Twin.** Un corpo umano ricostruito sulla mesh base di MakeHuman e adattato a sesso, età, peso e altezza. Collo, vita, fianchi, polpaccio e polso sono risolti sulla mesh in modo che le circonferenze coincidano con quelle misurate. Ogni distretto prende il colore della zona della barra dei suoi indici: blu sotto la norma, verde nella norma, rosso sopra. Il cuore pulsa alla frequenza misurata. Se il volume non si accorda con il peso (soggetti pesanti rispetto alle misure), il volume resta sotto il peso rilevato e la scheda lo segnala. Se il caricamento del corpo fallisce, resta il vecchio modello a sezioni ellittiche.

**Circolo.** Gli indici cardiovascolari nell'ordine in cui agiscono: cuore (frequenza, gittata sistolica, gittata, indice cardiaco, lavoro, RPP), arterie (pressione, pressione di pulsazione e media, rigidità, ePWV) e periferia (resistenza, shock index modificato). Gittata, gittata sistolica e resistenza sono stime da formule, non misure.

**Indici.** Raggruppati per area:

- Antropometria: BMI (Trefethen e classico), indice ponderale, intervallo di peso, indice di Grant e morfotipo, pesi ideali (Lorenz, Creff), collo, polpaccio corretto per BMI, superficie e volume corporeo.
- Distribuzione del grasso: vita/altezza, vita/fianchi, ABSI (z-score), BRI, conicità, AVI, BAI.
- Composizione corporea: grasso corporeo (CUN-BAE, RFM, US Navy), massa grassa e magra, FMI, FFMI, massa magra da altezza e peso (media di Boer, Hume e James).
- Metabolismo: metabolismo basale, media di Mifflin-St Jeor, Harris-Benedict e Katch-McArdle.
- Cuore e pressione: stato pressorio (ipoteso, normoteso, iperteso), frequenza (bradicardico, eucardico, tachicardico), frequenza massima, pressione di pulsazione e media, riserva cardiaca, indici emodinamici e di rigidità arteriosa, ePWV, rischio di ipertensione a 1, 2 e 4 anni (Framingham).

Sotto ogni valore c'è una barra con la zona di riferimento e un pallino sulla posizione. Il colore del valore è quello della zona. Non hanno barra gli indici senza un intervallo di popolazione (per esempio metabolismo basale, pesi ideali, superficie corporea) e la pressione, che ha il suo stato in parole.

Regole di classificazione:

- Pressione: iperteso se sistolica da 140 o diastolica da 90 mmHg (basta un valore); ipoteso sotto 90/60 se non è iperteso; normoteso negli altri casi.
- Frequenza cardiaca: la zona dipende dall'età (fasce degli script originali); sotto la fascia bradicardico, sopra tachicardico.
- FFMI: riferimento di Schutz 2002 (bioimpedenza) per gli uomini e per le donne fino a 34 anni. Per le donne oltre i 34 anni la barra non c'è, perché la tabella completa non era verificabile.

## Struttura del codice

- `lib/core`: indici (`indices.dart`), tabelle ABSI, modelli. Dart puro.
- `lib/twin`: corpo MakeHuman (`mh_data`, `mh_fit`, `mh_body`, `mh_view`) e vecchio modello a sezioni (`body_model`, `twin_view`).
- `lib/ui`: registro (`home_screen`, `subject_form`, `subject_screen`), inserimento, risultati, barra di riferimento.
- `lib/storage.dart`: soggetti e misure su `shared_preferences`. Le misure salvate prima del registro vengono raggruppate per sesso e data di nascita in soggetti da rinominare.
- `assets/mh/body.bin`: mesh e target di MakeHuman in formato binario compatto. Lo genera `tools/bake_mh.py` (`python3 tools/bake_mh.py <makehuman/data> assets/mh/body.bin`).
- `test`: valori di riferimento dal port Python del referto, adattamento del corpo contro il riferimento Python (`test/golden/mh_fit.json`), registro e barre.

## Sviluppo

    flutter create --platforms=android,web .   # genera le cartelle di piattaforma (non toccare lib/, assets/, pubspec.yaml)
    flutter pub get
    flutter test
    flutter run

## Build con GitHub Actions

Senza Flutter in locale:

- **Build APK**: parte a ogni push su `main`, esegue `flutter test` e, se passa, pubblica `somatwin.apk` come Release `build-N`. L'APK è firmato con la chiave di debug in `ci/`: serve a provarlo e ad aggiornare l'app senza disinstallarla, non al Play Store. Sul telefono vanno consentite le origini sconosciute.
- **Publish web**: compila la versione web e la pubblica su GitHub Pages (richiede il repository pubblico e Pages impostato su "GitHub Actions").

## Licenze e fonti

- Mesh e target del corpo: MakeHuman, assets CC0 1.0 (vedi `assets/mh/LICENSE.md`). Il codice di MakeHuman (AGPL) non è usato.
- Riferimento FFMI: Schutz Y, Kyle UUG, Pichard C. Fat-free mass index and fat mass index percentiles in Caucasians aged 18-98 y. Int J Obes 2002.
- Il repository non ha ancora una licenza per il codice: va scelta.
