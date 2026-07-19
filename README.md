# Lectura

Lectura este o aplicație personală Android-first care transformă cărți și documente în audio. Codul Flutter este comun pentru Android și iPhone.

## Ce funcționează în versiunea 1.0

- import local pentru PDF, EPUB, DOCX, TXT, Markdown, HTML și imagini;
- OCR local pentru paginile PDF scanate și fotografii;
- extragerea capitolelor EPUB în ordinea de lectură și a paragrafelor DOCX;
- coperți, capitole navigabile, bibliotecă locală și progres salvat;
- deschidere directă din meniul Android „Open with / Share”;
- împărțire inteligentă pe fragmente, fără tăierea propozițiilor când este posibil;
- mod **Neural local**, cu română și 10 stiluri de voce, fără cost pe minut;
- buffer anticipat cu două fragmente și playlist audio fără pauza de generare dintre ele;
- pregătirea integrală a unei cărți pentru ascultare offline;
- mod **Telefon**, folosind vocile instalate pe dispozitiv;
- mod opțional **OpenAI Premium**, cu Fable și alte voci neurale;
- profil automat per document: ficțiune, business, tehnic, dramatic, seară sau natural;
- alegerea manuală a vocii, stilului și vitezei;
- cache local pentru audio deja generat; schimbarea vitezei nu regenerează audio;
- redare în fundal, notificare media, controale pe ecranul blocat și temporizator de somn;
- temă luminoasă/întunecată după setarea telefonului;
- Android și cod compatibil iOS.

## Cele trei motoare de voce

### Neural local — recomandat

Folosește Supertonic 3 pentru a genera vocea direct pe dispozitiv. Modelul de aproximativ 400 MB se descarcă o singură dată, numai după confirmarea utilizatorului. După aceea, nu există cost pe fragment și textul nu este trimis unui serviciu vocal.

### Telefon

Nu trimite textul nicăieri și nu costă nimic. Folosește motorul TTS și pachetele de limbă instalate pe Android/iOS. Calitatea depinde de telefon și vocea instalată.

### OpenAI Premium

Folosește modelul `gpt-4o-mini-tts`. Aplicația trimite doar fragmentul curent pentru generarea audio, apoi păstrează rezultatul local. Utilizatorul este informat în aplicație că vocea este generată de AI.

Apelurile OpenAI necesită internet și generează costuri în contul API. Aplicația nu preîncarcă fragmente Premium, iar cărțile care foloseau vechiul mod Studio sunt migrate automat la Neural local la actualizare.

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

## Limite cunoscute

- fișierele vechi `.doc` și cărțile EPUB cu DRM nu sunt acceptate;
- modelul neural local ocupă aproximativ 400 MB și poate genera mai lent pe telefoane vechi;
- stilul se adaptează lecturii, dar nu atribuie încă o voce complet diferită fiecărui personaj;
- documentele foarte mari sunt extrase în memorie la import;
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

## Direcții viitoare

- voci distincte pentru personaje și dialog;
- backend și cont doar dacă aplicația va fi distribuită public;
- build iOS semnat și testat pe dispozitiv Apple.
