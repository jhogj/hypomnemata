# GRDBSQLCipher vendoring note

This directory is a minimal vendored copy of GRDB.swift 7.10.0 configured for
SQLCipher support with Swift Package Manager.

Reason: upstream GRDB 7.10.0 documents that SPM + SQLCipher requires a GRDB
fork or local package manifest modification. A plain dependency on
`groue/GRDB.swift` links system SQLite, so `PRAGMA cipher_version` is empty and
production vaults fail closed.

Source:

- Upstream: `https://github.com/groue/GRDB.swift.git`
- Version copied: 7.10.0
- Upstream revision used before vendoring: `36e30a6f1ef10e4194f6af0cff90888526f0c115`
- SQLCipher package: `https://github.com/sqlcipher/SQLCipher.swift.git`, 4.14.0

Local changes:

- `Package.swift` was replaced with a SQLCipher-specific manifest.
- The package depends on `SQLCipher.swift`.
- The `GRDB` target defines `SQLITE_HAS_CODEC` and `SQLCipher`.
- The `GRDBSQLite` system-library target was removed.
- The `GRDBSQLCipher` target is enabled.

Do not replace this with a direct `GRDB.swift` dependency unless SwiftPM gains
upstream traits that can select SQLCipher without a fork.
