# media scripts

PowerShell scripts for managing a Plex-based media library. These tools handle common homelab tasks: deduplicating DVR recordings, comparing directories, combining video segments with FFmpeg, tagging files with MediaInfo, and organizing folders.

---

## Prerequisites

- **PowerShell 5.1+** : required for all scripts
- **[FFmpeg](https://ffmpeg.org/download.html)** : required by `combine-recursive-v2.ps1`
- **[MediaInfo CLI](https://mediaarea.net/en/MediaInfo/Download/Windows)** : required by `mediainfo-adder.ps1`
- **Robocopy** : required by `Move-DVRDupesv3.ps1` (included with Windows)

---

## Scripts

### DVR & Duplicate Management

> Looking for general-purpose duplicate file removal? See [`delete_duplicates.ps1` and `delete_duplicates-v5.ps1`](../picard%20(music)/README.md) in the `picard (music)` folder : both work equally well on video and other file types.

#### `Move-DVRDupesv3.ps1`
Scans a source directory for media files and moves any that already exist in a destination (master) library to a separate duplicates folder. Uses fuzzy filename matching : it strips episode codes, bracketed tags, years, and network suffixes before comparing, so logically identical files are matched even if named differently. Supports `-DryRun` to preview actions without moving anything. Uses Robocopy for reliable moves over network shares.

```powershell
# Dry run : see what would be moved without touching any files
.\Move-DVRDupesv3.ps1 -SourceDirectory "\\nas\dvr" -DestinationDirectory "\\nas\plex\tv" -DupeDestinationDirectory "\\nas\dupes" -DryRun

# Live run
.\Move-DVRDupesv3.ps1 -SourceDirectory "\\nas\dvr" -DestinationDirectory "\\nas\plex\tv" -DupeDestinationDirectory "\\nas\dupes"
```

---

#### `dvr-file-compare.ps1`
Compares two directories and reports media files that exist in **both** : useful for confirming what's already been ingested into your library. Uses the same fuzzy filename cleaning as `Move-DVRDupesv3.ps1`. Outputs results to the console and exports a CSV.

```powershell
.\dvr-file-compare.ps1
# Prompts for: source directory, destination directory, output CSV path
```

---

#### `dvr-file-unique.ps1`
The inverse of `dvr-file-compare.ps1` : reports media files in the source that have **no match** in the destination. Use this to find recordings that haven't been added to your library yet.

```powershell
.\dvr-file-unique.ps1
# Prompts for: source directory, destination directory, output CSV path
```

---

### Video Processing

#### `combine-recursive-v2.ps1`
Recursively scans a root directory for subdirectories containing two or more media files, then uses FFmpeg to concatenate them into a single output file per folder. Files are joined in alphabetical order using FFmpeg's concat demuxer (stream copy : no re-encoding). Combined files are saved to the script's own directory, prefixed with the source subfolder name.

Set `$customFFmpegPath` in the script to your FFmpeg executable, or leave it empty to use FFmpeg from your system PATH.

```powershell
# Process subdirectories under the current directory
.\combine-recursive-v2.ps1

# Process a specific root
.\combine-recursive-v2.ps1 -RootDirectoryToSearch "D:\Videos\Raw"
```

---

### File Organization

#### `mover.ps1`
Moves `.mp4` files from a source directory into individual named subfolders in a destination directory. Each subfolder is named after the video file. Useful for organizing flat directories of videos into a Plex-friendly folder-per-show structure. Skips files that already exist at the destination to prevent overwriting.

```powershell
.\mover.ps1 -SourceDirectory "\\nas\inbox" -DestinationBaseDirectory "\\nas\plex\movies"
```

---

#### `plex-folder-organizer-tmdb-tvdb.ps1`
Moves subfolders based on whether their name contains a TMDB or TVDB ID tag (e.g., `Show Name {tmdb-12345}`). Useful for separating Plex-matched folders from unmatched ones. Interactively prompts for source/destination paths, ID type (`tmdb` or `tvdb`), and whether to move matching or non-matching folders.

```powershell
.\plex-folder-organizer-tmdb-tvdb.ps1
# Prompts for all inputs interactively
```

---

### Reporting & Utilities

#### `Directory-Crawler.ps1`
Maps a directory tree to a CSV file, with optional depth limiting. Each row represents one subdirectory and includes its full path, depth level, and individual folder names split into separate `Level_1`, `Level_2`, etc. columns : making it easy to analyze large folder hierarchies in Excel. Output is saved to `DirectoryStructure.csv` on the Desktop.

```powershell
.\Directory-Crawler.ps1
# Prompts for: root directory, search depth (optional)
```

---

#### `rsync-folder-text-file.ps1`
Generates a plain text file listing all subdirectory paths under a given root : formatted for use as an rsync source list. Useful when syncing a complex directory tree to another machine or NAS.

```powershell
.\rsync-folder-text-file.ps1
# Prompts for: source directory, output file path
```

---

#### `mediainfo-adder.ps1`
Renames media files to include technical specs extracted by MediaInfo CLI. The appended tag follows the format `[1080p AVC AAC 2.0]`, matching Plex and common media naming conventions. Skips files that already have a bracketed tag. Processes subdirectories recursively.

To preview renames without applying them, add `-WhatIf` to the `Rename-Item` call inside the script.

```powershell
.\mediainfo-adder.ps1 -MediaInfoPath "C:\Tools\MediaInfo\MediaInfo.exe" -DirectoryPath "D:\TV Shows"

# Process only .mkv and .ts files
.\mediainfo-adder.ps1 -MediaInfoPath "C:\Tools\MediaInfo\MediaInfo.exe" -DirectoryPath "D:\TV Shows" -Extensions "*.mkv", "*.ts"
```

---

## Supported file types

Most scripts target `.ts`, `.mp4`, and `.mkv` by default. Several scripts accept an `-Extensions` parameter to customize this.

---

## Notes

- Scripts that move or delete files log their actions to a CSV where possible.
- Always use `-DryRun` or `-WhatIf` on first run when working with large libraries or network shares.
- UNC paths (e.g., `\\server\share`) are supported throughout.
