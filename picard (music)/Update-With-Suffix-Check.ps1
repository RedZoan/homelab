<#
.SYNOPSIS
    Moves newer source files to Destination while consolidating Windows-style "(1)", "(2)" suffix duplicates.

.DESCRIPTION
    Handles a specific scenario common after re-tagging music: the Destination has both a clean copy
    ("song.flac") and one or more Windows duplicate copies ("song (1).flac", "song (2).flac"), while
    the Source has a freshly re-tagged version that is newer than all of them.

    For each Source file, the script:
      1. Mirrors the Source folder structure into the Destination to find the matching folder.
      2. Searches that folder for the exact filename OR any "(N)" suffix variants using regex.
      3. Compares timestamps : if Source is NEWER than the newest Destination match:
           a. Deletes ALL matching Destination variants (the clean copy and any "(N)" copies).
           b. Moves the Source file into Destination using its clean filename.
      4. After all files are processed, removes any empty subdirectories left behind in Source.

    Defaults to Dry Run mode ($DryRun = $true). Set to $false to execute deletes and moves.

.PARAMETER SourceDir
    Prompted interactively. The directory containing freshly re-tagged source files.

.PARAMETER DestDir
    Prompted interactively. The destination library directory to update.

.EXAMPLE
    # Dry run : preview which files would be updated and which Destination variants would be deleted
    .\Update-With-Suffix-Check.ps1

.NOTES
    - Set $DryRun = $false in the SAFETY CONFIGURATION block to perform actual operations.
    - This script is DESTRUCTIVE: it deletes Destination files and moves Source files.
    - Special characters in filenames (e.g., [ ] +) are handled via [regex]::Escape().
    - Only updates files where the Source is strictly NEWER : older or equal timestamps are skipped.
#>

# --- SAFETY CONFIGURATION ---
# $true  = Dry Run: list what would happen, no files moved or deleted (recommended first)
# $false = Live Run: ACTUALLY delete Destination variants and move Source files
$DryRun = $true
# ----------------------------

Write-Host "Smart Suffix Updater (Consolidate (1) (2) files)" -ForegroundColor Cyan
if ($DryRun) { Write-Host "!!! DRY RUN - LISTING ONLY !!!" -ForegroundColor Yellow }

# 1. Prompt for Directories
$SourceDir = Read-Host "Enter Source Path (e.g. D:\Music)"
$DestDir   = Read-Host "Enter Destination Path (e.g. \\Server\Share)"

$SourceDir = $SourceDir.TrimEnd('\')
$DestDir   = $DestDir.TrimEnd('\')

if (-not (Test-Path $SourceDir) -or -not (Test-Path $DestDir)) {
    Write-Error "Invalid paths. Please check your network connection."
    exit
}

# 2. Scan Source Files
$SourceFiles = Get-ChildItem -Path $SourceDir -Recurse -File
Write-Host "Scanning source files..." -ForegroundColor Gray

foreach ($SourceFile in $SourceFiles) {
    
    # A. Determine Relative Paths
    $RelativePath = $SourceFile.FullName.Substring($SourceDir.Length)
    $RelativeParentDir = $SourceFile.DirectoryName.Substring($SourceDir.Length)
    
    # B. Define Target Directory in Destination
    # Remove leading slash for Join-Path safety
    $CleanRelativeParent = $RelativeParentDir.TrimStart('\') 
    $TargetFolder = Join-Path -Path $DestDir -ChildPath $CleanRelativeParent

    # Only proceed if the folder exists in destination (Update Existing logic)
    if (Test-Path $TargetFolder) {
        
        # C. Build Regex to find "File.ext" AND "File (1).ext" in Target Folder
        $BaseName = [regex]::Escape($SourceFile.BaseName) # Escape special chars like [ or +
        $Extension = [regex]::Escape($SourceFile.Extension)
        
        # Regex Pattern: Starts with Name, Optional space+(digits), Ends with Extension
        $Pattern = "^$BaseName(\s\(\d+\))?$Extension$"

        # D. Find ALL matching files in the specific Destination Folder
        $DestMatches = Get-ChildItem -Path $TargetFolder -File | Where-Object { $_.Name -match $Pattern }

        if ($DestMatches) {
            # E. Find the "Newest" version currently in Destination
            # We sort descending so the newest timestamp is at index 0
            $NewestDest = $DestMatches | Sort-Object LastWriteTime -Descending | Select-Object -First 1

            # F. Compare: Is Source Newer than the Newest Destination copy?
            if ($SourceFile.LastWriteTime -gt $NewestDest.LastWriteTime) {
                
                Write-Host "Update Found: $($SourceFile.Name)" -ForegroundColor Green
                Write-Host "   Source Time: $($SourceFile.LastWriteTime)"
                Write-Host "   Dest Time:   $($NewestDest.LastWriteTime) (matched $($DestMatches.Count) files)"

                if (-not $DryRun) {
                    try {
                        # 1. Delete ALL matching destination variations (Cleanup the mess)
                        foreach ($Match in $DestMatches) {
                            Remove-Item -Path $Match.FullName -Force -ErrorAction Stop
                        }

                        # 2. Move Source to Destination (Using the clean Source Name)
                        $FinalDestPath = Join-Path -Path $TargetFolder -ChildPath $SourceFile.Name
                        Move-Item -Path $SourceFile.FullName -Destination $FinalDestPath -Force -ErrorAction Stop
                        
                        Write-Host "   [SUCCESS] Cleaned duplicates & Moved Source" -ForegroundColor Cyan
                    }
                    catch {
                        Write-Error "   [ERROR] $_"
                    }
                } else {
                    Write-Host "   [DRY RUN] Would delete $($DestMatches.Name) and move Source here." -ForegroundColor Yellow
                }
                Write-Host "------------------------------------------------"
            }
        }
    }
}

# --- STEP 3: CLEANUP EMPTY SOURCE FOLDERS ---
Write-Host "`n[CLEANUP] Checking for empty subfolders in Source..." -ForegroundColor Cyan

$SourceSubFolders = Get-ChildItem -Path $SourceDir -Recurse -Directory | Sort-Object FullName -Descending

foreach ($Folder in $SourceSubFolders) {
    # Force checks hidden files too
    $ContentCount = (Get-ChildItem -Path $Folder.FullName -Force).Count

    if ($ContentCount -eq 0) {
        if (-not $DryRun) {
            try {
                Remove-Item -Path $Folder.FullName -Force -ErrorAction Stop
                Write-Host "   Deleted Empty: $($Folder.FullName)" -ForegroundColor DarkGray
            }
            catch { Write-Error "   Failed to delete: $($Folder.FullName)" }
        } else {
            Write-Host "   [DRY RUN] Would delete empty: $($Folder.FullName)" -ForegroundColor Yellow
        }
    }
}

Write-Host "`nProcess Complete." -ForegroundColor Cyan