<div align="center">

# ⚔️ Valheim Launcher Generator

[![🇬🇧 English](https://img.shields.io/badge/🇬🇧-English-0078D4?style=for-the-badge)](#-english-version)
[![🇵🇱 Polski](https://img.shields.io/badge/🇵🇱-Polski-DC143C?style=for-the-badge)](#-wersja-polska)

</div>

---

<br>

## 🇬🇧 English Version

<div align="center">

**Generate a fully configured, encrypted launcher suite for your private Valheim server — in 4 steps.**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Windows-0078D4?logo=windows)](https://www.microsoft.com/windows)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

</div>

### What is this?

**Valheim Launcher Generator** is a Windows desktop application built with Flutter.  
It's a 4-step wizard that lets any private server admin generate a branded, ready-to-distribute set of **3 standalone executables** — configured and encrypted specifically for their server.

No coding required. Fill in the form, click **Generate**, get 3 `.exe` files.

### Generated Suite

| App | Purpose |
|---|---|
| `{ServerName} Launcher.exe` | Players launch Valheim with one click — auto-connects to your server |
| `{ServerName} Patcher.exe` | Admin tool — uploads mod packages to FTP (BepInEx) |
| `{ServerName} Updater.exe` | Checks for launcher updates and downloads them from FTP |

All three are standalone, portable Windows executables. No installation needed.

### Wizard Steps

```
Step 1 — Branding     →  Server name, background image/video
Step 2 — Server       →  Valheim IP, port, password
Step 3 — FTP          →  FTP host, port, username, password
Step 4 — Security     →  Generate unique encryption key (salt)
                              ↓
                        [ Generate ]
                              ↓
              output/{ServerName}/
              ├── {ServerName} Launcher/
              │   ├── {ServerName} Launcher.exe
              │   ├── flutter_windows.dll
              │   └── data/
              ├── {ServerName} Patcher/
              └── {ServerName} Updater/
```

### Key Features

- 🔐 **Encrypted credentials** — FTP passwords and server data are XOR-encrypted with SHA-256, never stored as plaintext
- 🎬 **Video background** — Launcher supports animated `.mp4` background per server branding
- 🌍 **Multilingual** — Polish / English (i18n via ARB)
- 📦 **Portable executables** — Each app runs standalone, no runtime required
- 🔄 **Auto-update** — Updater checks FTP version file and downloads newer launcher automatically
- 🧩 **BepInEx mod sync** — Patcher scans FTP, computes checksums, syncs mods to local Valheim
- 🔌 **FTP + SFTP** — Auto-detects which protocol the server supports

### Architecture

```
vaheim_launcher_generator/
├── lib/
│   ├── generator/           # 4-step wizard UI + state
│   ├── modules/
│   │   ├── launcher_module/ # → Launcher.exe
│   │   ├── patcher_module/  # → Patcher.exe
│   │   └── updater_module/  # → Updater.exe
│   ├── utils/
│   │   └── crypto_service.dart   # HMAC-SHA256 XOR encrypt/decrypt
│   └── build_service.dart        # Build pipeline orchestrator
└── test/
    └── crypto_service_test.dart  # 10 unit tests ✅
```

### Getting Started

```powershell
git clone https://github.com/PawelSzymanski89/valheim_launcher_generator.git
cd valheim_launcher_generator
flutter pub get
flutter run -d windows
```

### Commercial & Custom Orders

Need a custom-branded launcher suite for your server or community?

📧 **pawel@howtodev.it**  
🐙 **[github.com/PawelSzymanski89](https://github.com/PawelSzymanski89)**

---

<br>

## 🇵🇱 Wersja Polska

<div align="center">

**Stwórz własny, zaszyfrowany zestaw aplikacji dla swojego prywatnego serwera Valheim — w 4 krokach.**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Windows-0078D4?logo=windows)](https://www.microsoft.com/windows)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

</div>

### Co to jest?

**Valheim Launcher Generator** to desktopowa aplikacja Windows zbudowana we Flutterze.  
Działa jako kreator (wizard) w 4 krokach, który pozwala administratorowi prywatnego serwera Valheim wygenerować gotowy, markowy zestaw **3 samodzielnych plików `.exe`** — skonfigurowanych i zaszyfrowanych pod jego konkretny serwer.

Bez programowania. Wypełnij formularz, kliknij **Generuj**, odbierz 3 pliki `.exe`.

### Generowane aplikacje

| Aplikacja | Przeznaczenie |
|---|---|
| `{NazwaSerwera} Launcher.exe` | Gracze uruchamiają Valheim jednym kliknięciem — automatyczne połączenie z serwerem |
| `{NazwaSerwera} Patcher.exe` | Narzędzie admina — wysyłanie paczek modów na FTP (BepInEx) |
| `{NazwaSerwera} Updater.exe` | Sprawdza dostępność nowej wersji launchera i pobiera ją automatycznie |

Wszystkie trzy są przenośnymi plikami `.exe` — nie wymagają instalacji.

### Kroki kreatora

```
Krok 1 — Branding     →  Nazwa serwera, tło (obraz lub wideo)
Krok 2 — Serwer       →  Adres IP, port, hasło serwera Valheim
Krok 3 — FTP          →  Host, port, użytkownik, hasło FTP
Krok 4 — Bezpiecz.    →  Generowanie unikalnego klucza szyfrującego (salt)
                              ↓
                        [ Generuj ]
                              ↓
              output/{NazwaSerwera}/
              ├── {NazwaSerwera} Launcher/
              │   ├── {NazwaSerwera} Launcher.exe
              │   ├── flutter_windows.dll
              │   └── data/
              ├── {NazwaSerwera} Patcher/
              └── {NazwaSerwera} Updater/
```

### Kluczowe funkcje

- 🔐 **Szyfrowanie** — hasła FTP i dane serwera zaszyfrowane XOR+SHA-256, brak plaintextu w binarce
- 🎬 **Wideo w tle** — launcher obsługuje animowane tło `.mp4`, personalizowane dla każdego serwera
- 🌍 **Wielojęzyczność** — Polski / Angielski (i18n via ARB)
- 📦 **Przenośne exe** — każda aplikacja działa samodzielnie bez instalacji
- 🔄 **Auto-aktualizacja** — updater sprawdza plik wersji na FTP i pobiera nowszą wersję launchera
- 🧩 **Synchronizacja modów BepInEx** — patcher skanuje FTP, liczy sumy kontrolne, synchronizuje mody
- 🔌 **FTP + SFTP** — automatyczne wykrycie protokołu serwera

### Architektura

```
vaheim_launcher_generator/
├── lib/
│   ├── generator/           # Wizard 4-krokowy + zarządzanie stanem
│   ├── modules/
│   │   ├── launcher_module/ # → Launcher.exe
│   │   ├── patcher_module/  # → Patcher.exe
│   │   └── updater_module/  # → Updater.exe
│   ├── utils/
│   │   └── crypto_service.dart   # Szyfrowanie HMAC-SHA256 XOR
│   └── build_service.dart        # Orkiestrator budowania
└── test/
    └── crypto_service_test.dart  # 10 testów jednostkowych ✅
```

### Uruchomienie

```powershell
git clone https://github.com/PawelSzymanski89/valheim_launcher_generator.git
cd valheim_launcher_generator
flutter pub get
flutter run -d windows
```

### Kontakt komercyjny

Potrzebujesz dedykowanego launchera dla swojego serwera lub społeczności?

📧 **pawel@howtodev.it**  
🐙 **[github.com/PawelSzymanski89](https://github.com/PawelSzymanski89)**

---

*MIT © 2024 Paweł Szymański*
