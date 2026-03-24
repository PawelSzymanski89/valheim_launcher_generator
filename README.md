<div align="center">

# ⚔️ Valheim Launcher Generator

**Generate a fully configured, encrypted launcher suite for your private Valheim server — in 4 steps.**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Windows-0078D4?logo=windows)](https://www.microsoft.com/windows)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

</div>

---

## What is this?

**Valheim Launcher Generator** is a Windows desktop application built with Flutter.  
It's a 4-step wizard that lets any private server admin generate a branded, ready-to-distribute set of **3 standalone executables** — configured and encrypted specifically for their server.

No coding required. Fill in the form, click **Generate**, get 3 `.exe` files.

---

## Generated Suite

| App | Purpose |
|---|---|
| `{ServerName} Launcher.exe` | Players launch Valheim with one click — auto-connects to your server |
| `{ServerName} Patcher.exe` | Admin tool — scans FTP and uploads mod packages (BepInEx) |
| `{ServerName} Updater.exe` | Checks for launcher updates and downloads them from FTP automatically |

All three are standalone, portable Windows executables. No installation needed.

---

## Wizard Steps

```
Step 1 — Branding     →  Server name, background image/video
Step 2 — Server       →  Valheim IP, port, password  
Step 3 — FTP          →  FTP host, port, username, password
Step 4 — Security     →  Generate unique encryption key (salt)
                              ↓
                        [ Generate ]
                              ↓
              output/{ServerName}/
              ├── {ServerName} Launcher.exe
              ├── {ServerName} Patcher.exe
              └── {ServerName} Updater.exe
```

---

## Key Features

- 🔐 **Encrypted credentials** — FTP passwords and server data are XOR-encrypted with SHA-256, never stored as plaintext inside the binary
- 🎬 **Video background** — Launcher supports animated `.mp4` background per server branding
- 🌍 **Multilingual** — Polish / English (i18n via ARB)
- 📦 **Portable executables** — Each app runs standalone, no runtime required
- 🔄 **Auto-update** — Updater checks FTP version file and downloads newer launcher automatically
- 🧩 **BepInEx mod sync** — Patcher scans remote FTP tree, computes checksums, syncs mods to local Valheim
- ⚡ **Multi-connection FTP** — Concurrent FTP pool for fast file scanning
- 🔌 **FTP + SFTP** — Auto-detects which protocol the server supports

---

## Architecture

```
vaheim_launcher_generator/
├── lib/
│   ├── generator/           # 4-step wizard UI + Provider state
│   │   ├── steps/           # Step1–Step4 widgets
│   │   ├── config_manager.dart
│   │   └── wizard_page.dart
│   ├── modules/             # Source code of generated apps
│   │   ├── launcher_module/ # Flutter app → Launcher.exe
│   │   ├── patcher_module/  # Flutter app → Patcher.exe
│   │   └── updater_module/  # Flutter app → Updater.exe
│   ├── utils/
│   │   ├── crypto_service.dart   # HMAC-SHA256 XOR encrypt/decrypt
│   │   └── shared_salt.dart      # Saves salt to Windows Registry
│   └── build_service.dart        # Build pipeline orchestrator
├── assets/
│   ├── backgrounds/
│   └── locales/             # app_pl.arb, app_en.arb
├── profiles/                # Saved server profiles (JSON)
├── output/                  # Generated executables land here
└── test/
    └── crypto_service_test.dart   # 10 unit tests
```

---

## How Encryption Works

```
Generator                           Modules (runtime)
─────────────────────────────────   ─────────────────────────────────
salt (user-defined, 30+ chars)  →   salt stored in Windows Registry
                                         ↓
config JSON (plaintext)          →   config_encrypted.json (bundled asset)
    ↓ encrypt(config, salt)              ↓ decrypt(asset, salt_from_registry)
config_encrypted.json           →   DecryptedConfig { ftpHost, ftpPass, ... }
    ↓ inject into module assets
flutter build windows
    → {ServerName} Launcher.exe
```

**Algorithm:** Random 16-byte IV · HMAC-SHA256 key derivation · XOR stream cipher · Base64 output.  
Lightweight by design — this is a game launcher, not a bank.

---

## Tech Stack

| | |
|---|---|
| **Framework** | Flutter 3.x (Windows Desktop) |
| **State management** | Provider |
| **Encryption** | `crypto` (HMAC-SHA256 XOR) |
| **FTP** | `ftpconnect` |
| **SFTP** | `dartssh2` |
| **Video** | `media_kit` |
| **Persistence** | `shared_preferences` (Windows Registry) |
| **File ops** | `archive`, `path_provider`, `file_picker` |
| **i18n** | Flutter localization (ARB) |

---

## Getting Started

### Prerequisites

- Flutter SDK ≥ 3.x with Windows desktop enabled
- Git

### Run the Generator

```powershell
git clone https://github.com/PawelSzymanski89/valheim_launcher_generator.git
cd valheim_launcher_generator
flutter pub get
flutter run -d windows
```

### Run Unit Tests

```powershell
flutter test test/crypto_service_test.dart --reporter=expanded
```

Expected output: `+10: All tests passed!`

---

## Generating Your Server Suite

1. Launch the Generator
2. Fill in the 4 wizard steps with your server data
3. Click **Generuj / Generate**
4. Find your 3 `.exe` files in `output/{YourServerName}/`
5. Distribute `{ServerName} Updater.exe` to your players — it handles the rest

> ⚠️ **Keep your salt safe.** If the salt stored in the registry is lost, the modules can no longer decrypt their configuration. Back it up from Step 4.

---

## Contributing

Pull requests welcome. For major changes, open an issue first.

---

## License

MIT © 2024 Paweł Szymański
