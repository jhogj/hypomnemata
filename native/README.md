# Hypomnemata Native

This is the native macOS rewrite track for Hypomnemata.

Current status: Sprint 2 of the native rewrite is in progress. The existing
FastAPI/React app remains untouched and can keep serving as behavioral
reference while the native app is built out.

## Target

- macOS 14+
- Apple Silicon
- SwiftUI/AppKit native app
- SQLite via vendored GRDB 7.10.0 configured for SQLCipher.swift
- SQLCipher required for production vaults
- AES-GCM encrypted assets through CryptoKit
- Asset encryption key stored inside the SQLCipher vault, not in a plaintext file
- Temporary decrypted asset cache cleared on vault lock and application quit
- Vault lock discards database, repositories, asset store, keys, selection and capture UI even if cleanup reports an error
- Auto-lock after 15 minutes of inactivity
- Immediate vault lock on macOS sleep, screen sleep, and session resign-active notifications
- Vault passphrase change through SQLCipher rekey
- Empty passphrases rejected before vault open or rekey
- Native library sidebar backed by repository queries
- Combined filters for type, tag, folder, and FTS5 search
- Sidebar counts for total items, item kinds, tags, folders, and encrypted asset storage
- Native list/grid switcher for library items
- Basic item detail sheet with title, tags, note, body text editing, and individual delete

## External commands expected in product builds

```sh
brew install sqlcipher ffmpeg yt-dlp gallery-dl trafilatura
```

The app does not install these tools. `DependencyDoctor` reports what is
missing and the Homebrew command to install it.

## Local development

```sh
cd native
CLANG_MODULE_CACHE_PATH=/tmp/hypo-clang-cache SWIFTPM_HOME=/tmp/hypo-swiftpm-cache swift run --disable-sandbox HypomnemataNativeChecks
CLANG_MODULE_CACHE_PATH=/tmp/hypo-clang-cache SWIFTPM_HOME=/tmp/hypo-swiftpm-cache swift build --disable-sandbox --product HypomnemataMacApp
```

`HypomnemataNativeChecks` opens a real SQLCipher database, exercises CRUD,
FTS5, edit/delete flows, dependency checks, combined filters, folder queries,
persistent asset keys, AES-GCM asset encryption, temporary cache cleanup,
SQLCipher rekey, old-passphrase rejection, and then verifies that system
`sqlite3` cannot read the vault. The app path requires SQLCipher by default and
fails closed when it is unavailable.

## Sprint status

- Sprint 0: complete.
- Sprint 1: complete as of 2026-04-25.
- Sprint 2.1/2.2: complete as of 2026-04-25.
- Sprint 2.3: complete as of 2026-04-25.
- Next step: Sprint 2.4, full capture CRUD and encrypted assets.
