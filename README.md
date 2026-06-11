# homelab

A collection of PowerShell scripts and automation tools for managing a self-hosted home media server. Built around a Plex setup with DVR recordings and a MusicBrainz Picard music library, these scripts solve real problems : deduplicating recordings, syncing re-tagged files, organizing folders, combining video segments, etc.

Each script is written to be reusable, parameterized, and safe to run with dry-run modes where destructive operations are involved.

---

## What's inside

### [`media scripts/`](./media%20scripts/)

PowerShell scripts for managing a Plex-based media library and DVR recordings. Covers file comparison, duplicate detection, FFmpeg concatenation, MediaInfo tagging, and folder organization.

See the [media scripts README](./media%20scripts/README.md) for full documentation.

---

### [`picard (music)/`](./picard%20(music)/)

PowerShell scripts for managing a self-hosted music library using a MusicBrainz Picard re-tagging workflow. Covers syncing re-tagged files to a NAS, consolidating Windows-style `(1)` `(2)` suffix duplicates, SHA256-verified source cleanup, and batch Robocopy operations for large libraries.

See the [picard (music) README](./picard%20(music)/README.md) for full documentation.

---

## Skills demonstrated

- PowerShell scripting : parameters, pipeline processing, error handling, progress reporting
- Regex-based filename normalization for fuzzy file matching
- SHA256 hash verification for byte-for-byte file comparison
- Integration with external CLI tools (FFmpeg, MediaInfo, Robocopy)
- Hash table lookups for efficient large-directory comparison
- Long path (>260 character) handling via Robocopy and `\\?\` prefixes
- Network share (UNC path) compatible file operations
- CSV logging and reporting

---

## Setup

All scripts require **PowerShell 5.1 or later**. Some scripts have additional dependencies : see the README in each subfolder for details.

No installation needed. Clone the repo and run scripts directly from a PowerShell terminal:

```powershell
git clone https://github.com/RedZoan/homelab.git
cd homelab
```

---

## Repository description

> PowerShell scripts for managing a self-hosted Plex and music library : DVR deduplication, FFmpeg combining, MediaInfo tagging, Robocopy batch operations, and more.
