# Hypomnemata Native

This is the native macOS rewrite track for Hypomnemata.

Current status: foundation implementation for the rewrite plan. The existing
FastAPI/React app remains untouched and can keep serving as behavioral
reference while the native app is built out.

## Target

- macOS 14+
- Apple Silicon
- SwiftUI/AppKit native app
- SQLite via GRDB
- SQLCipher required for production vaults
- AES-GCM encrypted assets through CryptoKit

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

`HypomnemataNativeChecks` opens databases with plaintext SQLite because
SQLCipher is not available in every development environment. The app path
requires SQLCipher by default and fails closed when it is unavailable.
