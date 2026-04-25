# Hypomnemata Native

This is the native macOS rewrite track for Hypomnemata.

Current status: foundation implementation for the rewrite plan. The existing
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

`HypomnemataNativeChecks` opens a real SQLCipher database, then verifies that
system `sqlite3` cannot read it. The app path requires SQLCipher by default and
fails closed when it is unavailable.
