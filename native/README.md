# Hypomnemata Native

This is the native macOS rewrite track for Hypomnemata.

Current status: Sprint 7.2 of the native rewrite is complete. The existing
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
- Capture sheet with URL, file, and text modes
- Capture validation shared by app and checks: one source only, explicit http/https URL, local file URL, trimmed metadata and normalized tags
- File capture writes AES-GCM encrypted assets and records them in SQLite
- Capture creates real pending `jobs` rows instead of storing planned jobs in item metadata
- Jobs with missing executable dependencies are stored as recoverable `failed` rows with an actionable Homebrew command
- External capture entry points accept `http/https`, `hypomnemata://capture?url=...`, `hypomnemata://capture?text=...`, and AppKit Services pasteboard text/URLs
- Folder repository contracts support rename, delete, per-item listing, add, and remove
- Native folder UI supports create, rename, delete, add selected items, and per-item folder chips
- Zettelkasten repository contracts expose linked items and backlinks from `[[uuid|title]]` references
- Item detail shows links/backlinks and can insert `[[uuid|title]]` links with a basic search picker
- Item detail decrypts assets into `TemporaryCache` and previews images, PDFs, videos, and generic files
- Native thumbnail generation creates encrypted JPEG thumbnail assets for supported file captures
- Library list/grid displays thumbnails when available
- Videos can play inline from list/grid and continue from the same timestamp when opened in detail
- Native OCR extracts image/PDF text with Vision/PDFKit, updates item body text, and stores encrypted derived text assets
- Individual delete removes encrypted asset files associated with the item
- Batch selection and batch delete for visible library items
- Synthetic 10k-item check for list, FTS5 search, and batch delete
- `JobAutomation` runs `summarize`/`autotag` automatically after capture, with conservative autotag (skipped when manual tags exist)
- Manual retry of failed AI jobs from the detail sheet, incrementing `attempts`
- Detail sheet exposes per-job status with colored indicators (`pending`/`running`/`done`/`failed`) and inline retry
- LLM settings (URL / model / context limit) persisted inside the SQLCipher vault, with vault > env > default precedence resolved per field
- Persistent chat with the document via the `chat_messages` table, available when the item has at least 300 characters of body text
- `ItemChatService` builds a Portuguese-grounded system prompt that limits replies to the stored content and reuses existing message history
- Detail sheet exposes a chat toggle with streaming bubbles, blinking cursor, auto-scroll, and a destructive "clear conversation" action

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
folder rename/remove/delete flows, linked items and backlinks, link insertion UI, persistent asset keys, asset table registration, AES-GCM asset encryption,
native thumbnail generation, native OCR extraction, encrypted asset removal, decrypted preview cache, batch delete, a synthetic 10k-item performance
scenario, recoverable job failures for missing dependencies, `JobAutomation`
running summary/autotag with the IA fake client (including conservative
autotag and `unsupportedJobKind` for subprocess-backed jobs), job retry via
`incrementJobAttempts` + status reset, vault-backed LLM settings round-trip
plus vault-vs-env-vs-default precedence, `ItemChatService` streaming with
the system prompt grounding, history replay and rejection of empty content
or items below the 300-character threshold, plus `chat_messages`
append/history/clear and `ON DELETE CASCADE` from the item, temporary cache cleanup, SQLCipher
rekey, old-passphrase rejection, and then verifies that system `sqlite3`
cannot read the vault. The app path
requires SQLCipher by default and fails closed when it is unavailable.

The SwiftPM app target installs the AppKit Services handler in code. A
distribution `.app` still needs the corresponding `NSServices` declaration in
its Info.plist during packaging so macOS exposes it in the Services/Share UI.

## Sprint status

- Sprint 0: complete.
- Sprint 1: complete as of 2026-04-25.
- Sprint 2.1/2.2: complete as of 2026-04-25.
- Sprint 2.3: complete as of 2026-04-25.
- Sprint 2.4: complete as of 2026-04-25.
- Sprint 2.5: complete as of 2026-04-25.
- Sprint 2: complete as of 2026-04-25.
- Sprint 3.1: complete as of 2026-04-25.
- Sprint 3.2: complete as of 2026-04-25.
- Sprint 3.3: complete as of 2026-04-25.
- Sprint 3: complete as of 2026-04-25.
- Sprint 4.1: complete as of 2026-04-25.
- Sprint 4.2: complete as of 2026-04-25.
- Sprint 4.3: complete as of 2026-04-25.
- Sprint 4: complete as of 2026-04-25.
- Sprint 5.1: complete as of 2026-04-25.
- Sprint 5.2: complete as of 2026-04-25.
- Sprint 5.3: complete as of 2026-04-25.
- Sprint 5: complete as of 2026-04-25.
- Sprint 6 plan:
  - 6.1: complete as of 2026-04-25. LLM contracts and infrastructure, with fake-client checks and no required live network call.
  - 6.2: complete as of 2026-04-25. Item summary and autotags in the detail sheet.
  - 6.3: complete as of 2026-04-25. `JobAutomation` runs `summarize`/`autotag` automatically after capture; conservative autotag only when the item has no manual tags; manual retry of failed jobs; "Tarefas" section in the detail sheet with colored status and inline retry.
- Sprint 6: complete as of 2026-04-25.
- Sprint 7 plan:
  - 7.1: complete as of 2026-04-25. `LLMSettingsStore` persists overrides inside the SQLCipher vault; `LLMConfiguration.resolve(overrides:env:)` resolves URL/model/context limit independently with vault > env > default precedence; "IA local" section in Settings with save/clear and validation.
  - 7.2: complete as of 2026-04-25. `ItemChatService` streams replies grounded in the stored content; `chat_messages` table-backed history exposed by the repository; detail sheet toggle with streaming bubbles, cursor, auto-scroll and clear-conversation.
  - 7.3: streaming summary in the detail sheet.
- Next step: Sprint 7.3.
