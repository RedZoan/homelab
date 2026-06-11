<#
.SYNOPSIS
    Moves newer existing files from Source to Destination using Robocopy, with optional empty folder cleanup.

.DESCRIPTION
    Step 1 : File Move (Robocopy):
        Moves files from Source to Destination, but ONLY if:
          - The file already exists in Destination (/xl excludes "lonely" source-only files).
          - The Source version is NEWER than the Destination version (/xo excludes older files).
        This makes it safe for updating an existing library without accidentally adding new files.

    Step 2 : Empty Folder Cleanup (optional):
        After the move, scans the Source for empty subdirectories and deletes them.
        Folders are processed deepest-first to safely remove nested empty trees.
        Skip this step by passing the -SkipCleanup switch.

    Defaults to Dry Run mode ($DryRun = $true). Set to $false to execute moves and deletions.

.PARAMETER SkipCleanup
    When present, skips Step 2 (empty folder removal). Only the Robocopy file move runs.

.EXAMPLE
    # Dry run : preview which files would be moved and which empty folders would be removed
    .\Update-Network-Robocopy-Cleanup.ps1

.EXAMPLE
    # Live run, skipping the empty folder cleanup
    .\Update-Network-Robocopy-Cleanup.ps1 -SkipCleanup

.NOTES
    - Set $DryRun = $false in the SAFETY CONFIGURATION block to perform actual moves and deletions.
    - /fft allows a 2-second timestamp tolerance, recommended for NAS/network shares (FAT filesystem clock drift).
    - /xl + /xo together mean: only move files that already exist in Destination AND are older there.
    - Requires Robocopy (included with Windows).
#>
param(
    [switch]$SkipCleanup
)

# --- SAFETY CONFIGURATION ---
# $true  = Dry Run: list what would happen, no files moved or deleted (recommended first)
# $false = Live Run: MOVE files and DELETE empty folders
$DryRun = $true
# ----------------------------

Write-Host "Network File Updater & Cleaner" -ForegroundColor Cyan
if ($DryRun) { Write-Host "!!! DRY RUN - LISTING ONLY !!!" -ForegroundColor Yellow }
if ($SkipCleanup) { Write-Host "Note: Empty folder cleanup will be skipped (-SkipCleanup)" -ForegroundColor Gray }

# 1. Prompt for Directories
$SourceDir = Read-Host "Enter Source Path (e.g. \\Server\Share)"
$DestDir   = Read-Host "Enter Destination Path (e.g. Z:\Archive)"

# Trim trailing slashes to prevent Robocopy path-quoting issues
$SourceDir = $SourceDir.TrimEnd('\')
$DestDir   = $DestDir.TrimEnd('\')

if (-not (Test-Path $SourceDir) -or -not (Test-Path $DestDir)) {
    Write-Error "Invalid paths. Please check your network connection."
    exit
}

# --- STEP 1: FILE MOVE (ROBOCOPY) ---

$ArgsList = @(
    $SourceDir,
    $DestDir,
    "*.*",    # Match all files
    "/s",     # Recurse subdirectories
    "/mov",   # MOVE files (delete from source after successful copy)
    "/xo",    # eXclude Older: skip source files that are older than the destination copy
    "/xl",    # eXclude Lonely: skip source files that don't already exist in destination
    "/fft",   # Fat File Time: allow 2-second timestamp tolerance (useful for NAS/network shares)
    "/np",    # No Progress: suppress the per-file % progress bar
    "/r:1",   # Retry once on error
    "/w:1"    # Wait 1 second before retrying
)

if ($DryRun) {
    $ArgsList += "/l"   # /l = List only, no actual file operations
    Write-Host "`n[STEP 1 PREVIEW] Scanning files..." -ForegroundColor Gray
} else {
    Write-Host "`n[STEP 1 EXECUTION] Moving files..." -ForegroundColor Green
}

Write-Host "----------------------------------------------------------------"
& robocopy $ArgsList
Write-Host "----------------------------------------------------------------"


# --- STEP 2: CLEANUP EMPTY SOURCE FOLDERS ---

if (-not $SkipCleanup) {
    Write-Host "`n[STEP 2] Checking for empty subfolders in Source..." -ForegroundColor Cyan

    # Sort descending by path so deeper folders (e.g., Artist\Album) are processed before
    # their parents (Artist), allowing a full empty tree to be removed in one pass.
    $SourceSubFolders = Get-ChildItem -Path $SourceDir -Recurse -Directory | Sort-Object FullName -Descending

    foreach ($Folder in $SourceSubFolders) {
        # -Force includes hidden files in the count so truly empty folders aren't missed
        $ContentCount = (Get-ChildItem -Path $Folder.FullName -Force).Count

        if ($ContentCount -eq 0) {
            if (-not $DryRun) {
                try {
                    Remove-Item -Path $Folder.FullName -Force -ErrorAction Stop
                    Write-Host "   Deleted empty folder: $($Folder.FullName)" -ForegroundColor DarkGray
                }
                catch {
                    Write-Error "   Failed to delete: $($Folder.FullName) - $_"
                }
            } else {
                Write-Host "   [DRY RUN] Would delete empty folder: $($Folder.FullName)" -ForegroundColor Yellow
            }
        }
    }
} else {
    Write-Host "`n[STEP 2 SKIPPED] Empty folder cleanup skipped." -ForegroundColor Gray
}

Write-Host "`nProcess Complete." -ForegroundColor Cyan
if ($DryRun) {
    Write-Host "Set `$DryRun = `$false in the script to proceed with moving files and deleting folders." -ForegroundColor Yellow
}
