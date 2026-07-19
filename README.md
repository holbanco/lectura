# Lectura

Lectura este o aplicație personală Android-first care transformă cărți și documente în audio. Codul Flutter este comun pentru Android și iPhone.

## Ce funcționează în MVP

- import local pentru PDF cu text selectabil, EPUB, DOCX, TXT, Markdown și HTML;
- extragerea capitolelor EPUB în ordinea de lectură și a paragrafelor DOCX;
- bibliotecă locală, progres salvat și reluare de unde ai rămas;
- împărțire inteligentă pe fragmente, fără tăierea propozițiilor când este posibil;
- mod **Offline**, folosind vocile instalate pe telefon;
- mod **Studio**, cu 13 voci neurale și regie de lectură;
- profil automat per document: ficțiune, business, tehnic, dramatic, seară sau natural;
- alegerea manuală a vocii, stilului și vitezei;
- cache local pentru audio Studio deja generat;
- temă luminoasă/întunecată după setarea telefonului;
- Android și cod compatibil iOS.

## Cele două motoare de voce

### Offline

Nu trimite textul nicăieri și nu costă nimic. Folosește motorul TTS și pachetele de limbă instalate pe Android/iOS. Calitatea depinde de telefon și vocea instalată.

### Studio

Folosește modelul `gpt-4o-mini-tts`. Aplicația trimite doar fragmentul curent pentru generarea audio, apoi păstrează rezultatul local. Utilizatorul este informat în aplicație că vocea este generată de AI.

Apelurile Studio necesită internet și pot genera costuri în contul API. Modul Offline rămâne gratuit și complet local.

Cheia API este păstrată în Android Keystore / Apple Keychain. Această soluție BYOK este destinată instalării personale. Înainte de distribuirea publică, apelul trebuie trecut printr-un backend care păstrează cheia în afara aplicației.

## Pornire rapidă

Ai nevoie de Flutter stable, Android Studio și un Android SDK configurat.

```bash
flutter doctor
flutter pub get
flutter analyze
flutter test
flutter run
```

Dacă runner-ele native nu au fost generate încă:

```bash
./scripts/bootstrap_platforms.sh
```

### APK Android

```bash
flutter build apk --release
```

Fișierul rezultat este:

```text
build/app/outputs/flutter-apk/app-release.apk
```

Configurația actuală semnează build-ul personal cu cheia locală de debug. Înainte de Google Play trebuie creată o cheie privată de release și configurată semnarea oficială.

### Build automat

Workflow-ul `.github/workflows/android.yml` rulează analiza, testele și produce un APK descărcabil ca artifact. Este suficient ca proiectul să fie urcat într-un repository GitHub și workflow-ul să fie pornit manual.

## iPhone

După generarea platformei iOS cu scriptul de mai sus:

```bash
flutter build ios --release
```

Build-ul final și instalarea necesită un Mac cu Xcode și un Apple ID. Pentru instalare permanentă/distribuție este necesar Apple Developer Program.

## Limite cunoscute ale MVP-ului

- PDF-urile scanate ca imagini nu au încă OCR;
- fișierele vechi `.doc` și cărțile EPUB cu DRM nu sunt acceptate;
- stilul se aplică per document, nu câte o voce distinctă pentru fiecare personaj;
- documentele foarte mari sunt extrase în memorie la import;
- redarea poate continua când aplicația intră în fundal, dar controalele media de pe ecranul blocat și un serviciu Android foreground dedicat sunt planificate pentru versiunea următoare;
- o cheie API în aplicația personală este protejată de sistemul de operare, dar nu trebuie folosită într-un APK distribuit public.

## Structură

```text
lib/
  models/        datele bibliotecii și profilurile de lectură
  services/      import, persistență, TTS offline/Studio, player
  screens/       bibliotecă, cititor, setări
  core/          temă și culori
test/            teste pentru chunking, detecția stilului și persistență
```

## Următoarea versiune recomandată

1. OCR local pentru PDF-uri scanate și poze;
2. background audio complet cu notificare și controale pe lock screen;
3. „Director AI” care detectează personaje și atribuie voci diferite dialogurilor;
4. import din meniul Android „Share/Open with Lectura”;
5. copertă și capitole navigabile;
6. pregătirea integrală a unei cărți pentru ascultare offline;
7. backend securizat și cont dacă aplicația va fi oferită și altor persoane.
