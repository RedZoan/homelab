<#
.SYNOPSIS
    Deletes files in a Source directory that have an identical copy in a Destination directory.

.DESCRIPTION
    Scans all files in the Source directory recursively. For each file, checks whether an
    identically-named file exists at the same relative path in the Destination. If it does,
    compares file sizes first (fast check), then SHA256 hashes (deep check). Only deletes
    the Source file if both checks pass, guaranteeing a true byte-for-byte match.

    Defaults to Dry Run mode : set $DryRun = $true in the CONFIGURATION block below to
    preview what would be deleted before committing to any changes.

    This script is DESTRUCTIVE when $DryRun = $false. Always do a dry run first.

.PARAMETER SourceDir
    Prompted interactively. The directory whose files will be deleted if matched.

.PARAMETER DestDir
    Prompted interactively. The reference directory. Files here are never modified.

.EXAMPLE
    # Run with default Dry Run mode to preview what would be deleted
    .\Dedupe-Source.ps1

.NOTES
    - Set $DryRun = $false in the script to perform actual deletions.
    - Uses SHA256 hashing for content verification after a file-size pre-check.
    - Only deletes files where the Destination has an exact path + content match.
#>

# --- CONFIGURATION ---
# $true  = Dry Run: report what would be deleted, but don't delete anything (recommended first)
# $false = Live Run: actually delete matched files from Source
$DryRun = $true
# ---------------------

Write-Host "Duplicate File Remover (Source vs Destination)" -ForegroundColor Cyan
if ($DryRun) { Write-Host "!!! DRY RUN MODE ACTIVE - NO FILES WILL BE DELETED !!!" -ForegroundColor Yellow }

# 1. Prompt for Directories
$SourceDir = Read-Host "Enter the full path of the SOURCE directory (Files here will be deleted)"
$DestDir   = Read-Host "Enter the full path of the DESTINATION directory (Files here are the reference)"

# 2. Validate Paths
if (-not (Test-Path $SourceDir) -or -not (Test-Path $DestDir)) {
    Write-Error "One or both paths are invalid or not accessible. Please check your network shares/paths."
    exit
}

# 3. Get all files in Source (Recursive)
Write-Host "Scanning source directory..." -ForegroundColor Gray
$SourceFiles = Get-ChildItem -Path $SourceDir -Recurse -File

foreach ($SourceFile in $SourceFiles) {

    # Build the relative path from the source root (e.g., "\Artist\Album\track.flac")
    $RelativePath = $SourceFile.FullName.Substring($SourceDir.Length)

    # Mirror that relative path into the Destination to find the expected counterpart
    $DestFilePath = Join-Path -Path $DestDir -ChildPath $RelativePath

    # 4. Check if the file exists at the same relative path in the Destination
    if (Test-Path $DestFilePath) {
        $DestFile = Get-Item $DestFilePath

        # 5. Fast check: file sizes must match before hashing
        if ($SourceFile.Length -eq $DestFile.Length) {

            # 6. Deep check: compare SHA256 hashes to confirm byte-for-byte identity
            Write-Host "Checking hash for: $RelativePath" -NoNewline

            $SourceHash = Get-FileHash -Path $SourceFile.FullName -Algorithm SHA256
            $DestHash   = Get-FileHash -Path $DestFile.FullName -Algorithm SHA256

            if ($SourceHash.Hash -eq $DestHash.Hash) {
                Write-Host " [MATCH] -> DELETING" -ForegroundColor Red

                if (-not $DryRun) {
                    try {
                        Remove-Item -Path $SourceFile.FullName -Force -ErrorAction Stop
                    }
                    catch {
                        Write-Error "Failed to delete $($SourceFile.FullName): $_"
                    }
                } else {
                    Write-Host "(Skipped delete due to DryRun)" -ForegroundColor Gray
                }
            } else {
                Write-Host " [NO MATCH] (Hashes differ)" -ForegroundColor Green
            }
        }
        # If sizes differ, the files are definitely not identical : skip silently
    }
    # If no counterpart exists in Destination : skip silently
}

Write-Host "`nProcess Complete." -ForegroundColor Cyan
if ($DryRun) { Write-Host "Set `$DryRun = `$false inside the script to perform actual deletions." -ForegroundColor Yellow }
