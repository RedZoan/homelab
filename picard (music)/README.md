# picard (music)

PowerShell scripts for managing a self-hosted music library : built around a MusicBrainz Picard re-tagging workflow. These scripts handle the common aftermath of a mass re-tag: updating changed files to a NAS, consolidating duplicate copies, removing confirmed originals once the library is clean, and generating batch lists for large Robocopy operations.

---

## Prerequisites

- **PowerShell 5.1+** : required for all scripts
- **Robocopy** : required by `Update-Network-Robocopy-Cleanup.ps1`, `robocopy-from-list-v3.ps1`, and `Directory-Crawler-Robocopy.ps1` (included with Windows)

---

## Safety note

Several scripts move or delete files. All of them default to **Dry Run mode** : they will report what *would* happen without touching anything. Always run in dry run mode first to verify the output before setting `$DryRun = $false` or removing `-WhatIf`.

---

## Scripts

### Duplicate Detection & Removal

#### `delete_duplicates.ps1`
Finds and deletes Windows-style duplicate copies (`file (1).ext`, `file (2).ext`) that exist in the same folder as the original. Confirms a size match within a configurable byte tolerance before deleting. Logs every action to a CSV. Use `-WhatIf` for a safe dry run and `-DebugMode` for verbose output.

```powershell
# Dry run
.\delete_duplicates.ps1 -Path "C:\Music" -LogFilePath "C:\temp\log.csv" -WhatIf

# Live run with a 500-byte size tolerance
.\delete_duplicates.ps1 -Path "C:\Music" -LogFilePath "C:\temp\log.csv" -SizeToleranceBytes 500
```

---

#### `delete_duplicates-v5.ps1`
An advanced duplicate finder suited to music libraries where filenames may differ beyond a simple `(1)` suffix. Detects two types of duplicates: simple numbered copies (`song.flac` / `song (1).flac`) and renamed variants where one name is a prefix of another (`song.flac` / `song (FLAC 96kHz) -SOURCE.flac`). Supports a `-ReportOnly` mode that generates a CSV for manual review without deleting anything. The `-Delete` parameter controls whether the smaller or larger file of a pair is removed. Includes long-path support (>260 characters) via the `\\?\` prefix.

```powershell
# Generate a report of potential duplicates for review (no deletions)
.\delete_duplicates-v5.ps1 -Path "C:\Music" -LogFilePath "C:\temp\report.csv" -ReportOnly

# Dry run, targeting the larger file of each pair
.\delete_duplicates-v5.ps1 -Path "C:\Music" -LogFilePath "C:\temp\log.csv" -Delete Larger -WhatIf

# Live run with default settings (deletes the smaller file)
.\delete_duplicates-v5.ps1 -Path "C:\Music" -LogFilePath "C:\temp\log.csv"
```

---

#### `Dedupe-Source.ps1`
Deletes files from a Source directory that have a byte-for-byte identical copy in a Destination directory. Uses a two-step check: file size first (fast), then SHA256 hash (definitive). Only deletes when both match, and only from the Source : the Destination is never modified. Useful for clearing out a staging folder once its contents have been confirmed in the main library.

```powershell
# Defaults to Dry Run : set $DryRun = $false in the script to delete
.\Dedupe-Source.ps1
# Prompts for: source directory, destination directory
```

---

### File Syncing & Updates

#### `Update-Network-Robocopy-Cleanup.ps1`
Moves files from Source to Destination using Robocopy, but only if the file already exists in Destination and the Source version is newer. This makes it safe to run repeatedly : it won't add new files, only update existing ones. Optionally cleans up empty subdirectories left behind in the Source after the move.

Pass `-SkipCleanup` to run only the file move (Step 1) without the empty folder removal (Step 2).

```powershell
# Dry run (default) : preview which files would move and which empty folders would be removed
.\Update-Network-Robocopy-Cleanup.ps1

# Live run, skip the empty folder cleanup
.\Update-Network-Robocopy-Cleanup.ps1 -SkipCleanup

# Set $DryRun = $false in the script to execute
```

---

#### `Update-With-Suffix-Check.ps1`
Handles a specific post-Picard scenario: the Destination has both a clean copy and Windows-style `(1)`, `(2)` suffix duplicates, while the Source has a freshly re-tagged version that is newer than all of them. For each matching file, it deletes all Destination variants (clean + numbered copies) and moves the Source file in using the clean filename. Cleans up empty Source subdirectories at the end.

```powershell
# Dry run (default) : preview which files would be updated
.\Update-With-Suffix-Check.ps1

# Set $DryRun = $false in the script to execute
```

---

### Batch Operations

#### `text-file-folder-sorter.ps1`
Reads a master list of folder paths and splits it into alphabetical batch text files (A.txt, B.txt, ..., _Numbers.txt, _Special.txt) containing only top-level (artist-level) directories. The output files are designed to feed directly into `robocopy-from-list-v3.ps1` for large batch copy operations.

```powershell
.\text-file-folder-sorter.ps1
# Prompts for: master list file, source root path, output directory
```

---

#### `robocopy-from-list-v3.ps1`
Reads all `.txt` files in a directory and uses Robocopy to copy each listed folder to a destination. Each `.txt` file gets its own subdirectory under the destination root (named after the file). Designed to run against the output of `text-file-folder-sorter.ps1`. All Robocopy output is appended to a single log file across all batches.

```powershell
.\robocopy-from-list-v3.ps1 `
    -listFileDirectory "C:\temp\batchlists" `
    -sourceRoot "\\nas\music" `
    -destinationRoot "D:\Backup" `
    -logFilePath "D:\Backup\robocopy.log"
```

---

### Utilities

#### `Directory-Crawler-Robocopy.ps1`
Maps a directory tree to a CSV file using Robocopy in list-only mode, bypassing the 260-character Windows path limit that can cause `Get-ChildItem` to fail on deeply nested music libraries. Output format is identical to `Directory-Crawler.ps1` in the media scripts folder: each row includes Depth, FullName, and Level_1, Level_2, ... columns. Results are saved to `DirectoryStructure.csv` on your Desktop.

```powershell
.\Directory-Crawler-Robocopy.ps1
# Prompts for: root directory, search depth (optional)
```

---

## Typical workflow

1. Re-tag your music library with MusicBrainz Picard : this produces updated files in a staging folder.
2. Use **`Update-With-Suffix-Check.ps1`** or **`Update-Network-Robocopy-Cleanup.ps1`** to push newer files to the NAS, replacing any existing copies including `(1)` suffix variants.
3. Use **`Dedupe-Source.ps1`** to confirm the staging files made it to the NAS and delete the confirmed copies from staging.
4. Use **`delete_duplicates.ps1`** or **`delete_duplicates-v5.ps1`** to clean up any `(1)` / `(2)` duplicates that accumulated in the NAS library.
5. For large initial migrations: use **`text-file-folder-sorter.ps1`** to split the library into alphabetical batches, then **`robocopy-from-list-v3.ps1`** to copy each batch.

---

## Notes

- Scripts that move or delete files log their actions to a CSV where applicable.
- Always use `$DryRun = $true` or `-WhatIf` on first run : especially on network shares where mistakes are harder to undo.
- UNC paths (e.g., `\\nas\music`) are supported throughout.
