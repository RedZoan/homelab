<#
.SYNOPSIS
    Scans a source directory for media files, compares them against a destination directory based on a cleaned filename,
    and moves any duplicates found in the source to a dedicated duplicates directory.

.DESCRIPTION
    This script is designed to handle large collections of files efficiently, making it suitable for use on network shares.
    It optimizes memory usage by processing files in a stream (using the pipeline) rather than loading entire directory listings into memory.

    To find logical duplicates, it first "cleans" filenames by removing common patterns like series/episode numbers (S01E01),
    years in parentheses, bracketed information, and common network suffixes.

    For file operations, it uses the robust Robocopy utility to ensure reliable file moves, especially over potentially unstable network connections.

.PARAMETER SourceDirectory
    The full path to the source directory to scan for duplicate files. UNC paths (e.g., \\server\share) are supported.

.PARAMETER DestinationDirectory
    The full path to the destination/master directory to compare against.

.PARAMETER DupeDestinationDirectory
    The full path to the directory where duplicate files from the source will be moved.

.PARAMETER DryRun
    A switch parameter. If included, the script will only report the actions it would take (i.e., which files it would move)
    without actually moving any files. This is highly recommended for the first run.

.EXAMPLE
    PS C:\> .\move_duplicate_media.ps1 -SourceDirectory "\\nas\dvr_recordings" -DestinationDirectory "\\nas\plex\tv_shows" -DupeDestinationDirectory "\\nas\dvr_duplicates"
    Scans the source, compares against the destination, and moves any found duplicates to the specified folder.

.EXAMPLE
    PS C:\> .\move_duplicate_media.ps1 -Source "C:\New Downloads" -Dest "D:\Media" -Dupe "C:\Dupes" -DryRun
    Performs a "dry run". It will create a report of files that would be moved, but no files will actually be changed.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, HelpMessage = "Enter the FULL path to the SOURCE directory.")]
    [string]$SourceDirectory,

    [Parameter(Mandatory = $true, HelpMessage = "Enter the FULL path to the DESTINATION directory.")]
    [string]$DestinationDirectory,

    [Parameter(Mandatory = $true, HelpMessage = "Enter the FULL path for the DUPLICATES directory.")]
    [string]$DupeDestinationDirectory,

    [Switch]$DryRun
)

# --- Configuration ---

# Define the allowed file extensions for comparison and moving.
$AllowedExtensions = @(".ts", ".mp4", ".mkv")

# --- Functions ---

function Clean-FileName {
    param (
        [string]$FileName
    )
    # Get the base name (filename without extension)
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    
    # Perform a series of replacements using regular expressions to "clean" the name for comparison.
    $cleaned = $baseName -replace ' - S\d{2}E\d{2,3}', '' # 1. Remove season/episode patterns (e.g., " - S01E02")
    $cleaned = $cleaned -replace '\s*\[.*?\]', ''          # 2. Remove bracketed info (e.g., " [1080p]")
    $cleaned = $cleaned -replace '\s*\(\d{4}\)', ''      # 3. Remove year in parentheses (e.g., " (2023)")
    $cleaned = $cleaned -replace ' NBC\b', ''             # 4. Remove common network suffixes (e.g., " NBC")
    
    return $cleaned.Trim()
}

# --- Initialization ---

Write-Host "Script started."
if ($DryRun) {
    Write-Host "Running in DRY RUN mode. No files will be moved." -ForegroundColor Yellow
}

# Ensure source and destination directories exist before proceeding.
if (-not (Test-Path $SourceDirectory)) {
    Write-Error "Source directory not found: $SourceDirectory"
    exit 1
}
if (-not (Test-Path $DestinationDirectory)) {
    Write-Error "Destination directory not found: $DestinationDirectory"
    exit 1
}

# Ensure the duplicate destination directory exists. Create it if it doesn't.
if (-not (Test-Path $DupeDestinationDirectory)) {
    Write-Host "Creating duplicate destination directory: $DupeDestinationDirectory"
    New-Item -Path $DupeDestinationDirectory -ItemType Directory -Force | Out-Null
}

# --- Main Logic ---

# 1. Build a lookup table of cleaned filenames from the destination directory for fast comparison.
Write-Host "Scanning destination directory and building lookup table..."
$DestinationFileLookup = @{}
try {
    # This approach processes each file object as it's found, which is more memory-friendly than storing them all in an array first.
    Get-ChildItem -Path $DestinationDirectory -Recurse -File |
        Where-Object { $AllowedExtensions -contains $_.Extension.ToLower() } |
        ForEach-Object -Process {
            $cleanedName = Clean-FileName -FileName $_.Name
            # If the cleaned name isn't already a key, add it. The value is the full path.
            if (-not $DestinationFileLookup.ContainsKey($cleanedName)) {
                $DestinationFileLookup[$cleanedName] = $_.FullName
            }
        }
    Write-Host "Destination scan complete. Found $($DestinationFileLookup.Count) unique media files."
}
catch {
    Write-Error "An error occurred while scanning the destination directory: $($_.Exception.Message)"
    exit 1
}


# 2. Stream source files, compare against the lookup table, and move if duplicate.
Write-Host "Scanning source directory and comparing files..."
$sourceFiles = Get-ChildItem -Path $SourceDirectory -Recurse -File | Where-Object { $AllowedExtensions -contains $_.Extension.ToLower() }
$totalSourceFiles = ($sourceFiles | Measure-Object).Count
$processedCount = 0

# The output of this loop is collected into the $MovedFilesReport variable. This is more efficient than using `+=`.
$MovedFilesReport = foreach ($sourceFile in $sourceFiles) {
    $processedCount++
    Write-Progress -Activity "Processing Source Files" -Status "Comparing $($sourceFile.Name)" -PercentComplete (($processedCount / $totalSourceFiles) * 100)

    $cleanedSourceName = Clean-FileName -FileName $sourceFile.Name

    # Check if the cleaned source filename exists in our destination lookup table.
    if ($DestinationFileLookup.ContainsKey($cleanedSourceName)) {
        $destinationMatchPath = $DestinationFileLookup[$cleanedSourceName]
        Write-Host "Duplicate found: '$($sourceFile.Name)' matches '$([System.IO.Path]::GetFileName($destinationMatchPath))'" -ForegroundColor Green
        
        # Determine the destination path, preserving the subdirectory structure from the source.
        # This makes the duplicate archive easier to navigate and resolves potential Robocopy pathing issues.
        $relativeSubPath = $sourceFile.DirectoryName.Substring($SourceDirectory.Length)
        $finalDestinationDirectory = Join-Path -Path $DupeDestinationDirectory -ChildPath $relativeSubPath
        $NewDupeFilePath = Join-Path -Path $finalDestinationDirectory -ChildPath $sourceFile.Name
        
        $moveSuccess = $false
        
        if ($DryRun) {
            Write-Host "  [DRY RUN] Would move '$($sourceFile.FullName)' to '$NewDupeFilePath'" -ForegroundColor Yellow
            $moveSuccess = $true # In dry run, we assume success for reporting purposes.
        }
        else {
            # Ensure the specific destination subdirectory exists before attempting to move the file.
            if (-not (Test-Path -Path $finalDestinationDirectory)) {
                try {
                    New-Item -Path $finalDestinationDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
                }
                catch {
                    Write-Warning "Failed to create destination directory '$finalDestinationDirectory'. Error: $($_.Exception.Message)"
                    # Skip to the next file if we can't create the directory.
                    continue
                }
            }

            Write-Host "  Moving file using Robocopy..."
            
            # Call Robocopy with the specific subdirectory as the destination.
            & robocopy.exe $sourceFile.DirectoryName $finalDestinationDirectory $sourceFile.Name /MOV /R:2 /W:5 /NJH /NJS /NP /NFL /NDL *> $null
            $exitCode = $LASTEXITCODE

            # Robocopy exit codes < 8 indicate success (with or without files copied, or extra files present).
            # An exit code of 1 means at least one file was copied successfully.
            # See https://ss64.com/nt/robocopy-exit.html for details.
            if ($exitCode -lt 8) {
                Write-Host "  Successfully moved '$($sourceFile.FullName)' to '$NewDupeFilePath'"
                $moveSuccess = $true
            }
            else {
                Write-Warning "Robocopy failed to move '$($sourceFile.FullName)' with exit code $exitCode."
                Write-Warning "To see detailed Robocopy output for debugging, remove ' *> `$null' from the script's robocopy command."
            }
        }

        # If the move was successful (or if it's a dry run), create a record for the report.
        if ($moveSuccess) {
            # Output a custom object to the pipeline. It will be collected in $MovedFilesReport.
            [PSCustomObject]@{
                OriginalSourcePath        = $sourceFile.FullName
                MovedToPath               = $NewDupeFilePath
                SourceFileName            = $sourceFile.Name
                CleanedFileName           = $cleanedSourceName
                MatchedDestinationPath    = $destinationMatchPath
                MatchedDestinationFile    = [System.IO.Path]::GetFileName($destinationMatchPath)
                Status                    = if ($DryRun) { "Identified for Move" } else { "Moved Successfully" }
            }
        }
    }
}
Write-Progress -Activity "Processing Source Files" -Completed


# 3. Generate a report of the actions taken.
if ($MovedFilesReport.Count -gt 0) {
    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $reportAction = if ($DryRun) { "DryRun" } else { "MovedDuplicates" }
    $ReportFileName = "$($reportAction)_Report_$($Timestamp).csv"
    $ReportFilePath = Join-Path -Path $DupeDestinationDirectory -ChildPath $ReportFileName

    Write-Host "`n--- Summary ---"
    $MovedFilesReport | Format-Table -Property Status, SourceFileName, MatchedDestinationFile, CleanedFileName -AutoSize
    
    try {
        $MovedFilesReport | Export-Csv -Path $ReportFilePath -NoTypeInformation -Encoding UTF8
        Write-Host "Comparison complete. Processed $($MovedFilesReport.Count) duplicate file(s)." -ForegroundColor Cyan
        Write-Host "Report exported to: $ReportFilePath" -ForegroundColor Cyan
    }
    catch {
        Write-Error "Failed to export report to '$ReportFilePath': $($_.Exception.Message)"
    }
}
else {
    Write-Host "`nComparison complete. No duplicate files were found in the source directory."
}

Write-Host "Script finished."


