<#
.SYNOPSIS
    Recursively searches for and deletes duplicate files, or generates a report of potential duplicates.

.DESCRIPTION
    This script searches a specified root folder and its subfolders to find and delete duplicate files.
    The script uses a powerful comparison logic that can identify two types of duplicates:
    1. Simple duplicates where a number is appended, e.g., "file.txt" and "file (1).txt".
    2. Renamed duplicates where one filename is a longer version of another, e.g., "song.flac" and "song (FLAC 96kHz) -SOURCE.flac".

    In deletion mode, after finding a matching pair within the size tolerance, the script can be
    configured to delete either the smaller or the larger file of the pair.

    Using the -ReportOnly switch changes this behavior. The script will find all potential duplicates based on name alone
    and generate a CSV report with file size information for manual review, without deleting anything.

.PARAMETER Path
    The starting folder path to search recursively. This parameter is mandatory.

.PARAMETER LogFilePath
    The full path for the CSV log/report file that will be created or appended to. This parameter is mandatory.

.PARAMETER SizeToleranceBytes
    The maximum allowed difference in bytes for a file to be considered a match for deletion. Not used with -ReportOnly. Defaults to 100 bytes.

.PARAMETER Delete
    Choose whether to delete the 'Smaller' or 'Larger' file of a duplicate pair. Defaults to 'Smaller'.

.PARAMETER ReportOnly
    A switch that, when present, creates a CSV report of all name-based potential duplicates without deleting any files.

.PARAMETER DebugMode
    A switch that, when present, enables highly verbose console output for troubleshooting.

.EXAMPLE
    # Generate a CSV report of all potential duplicates for manual review.
    .\delete_duplicates.ps1 -Path "C:\Music" -LogFilePath "C:\temp\report.csv" -ReportOnly

.EXAMPLE
    # Perform a dry run, targeting the LARGER file of each pair for deletion.
    .\delete_duplicates.ps1 -Path "C:\Music" -LogFilePath "C:\temp\log.csv" -Delete 'Larger' -WhatIf

.NOTES
    Version: 2.6
    - Fixed a string termination parsing error in the -ReportOnly section.
    - Added -Delete parameter with 'Smaller' or 'Larger' options to control which file in a pair is deleted.
    - Default behavior is to delete the smaller file.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter the root path to search for duplicate files.")]
    [string]$Path,

    [Parameter(Mandatory = $true, HelpMessage = "Enter the path for the log file (e.g., C:\temp\deletion_log.csv).")]
    [string]$LogFilePath,

    [Parameter(Mandatory = $false, HelpMessage = "The maximum allowed size difference in bytes. Defaults to 100.")]
    [int]$SizeToleranceBytes = 100,

    [Parameter(Mandatory = $false, HelpMessage = "Choose whether to delete the 'Smaller' or 'Larger' file of a duplicate pair. Defaults to 'Smaller'.")]
    [ValidateSet('Smaller', 'Larger')]
    [string]$Delete = 'Smaller',

    [Parameter(Mandatory = $false, HelpMessage = "Generate a CSV report of potential duplicates without deleting any files.")]
    [switch]$ReportOnly,

    [Parameter(Mandatory = $false, HelpMessage = "Enable verbose debug output to the console.")]
    [switch]$DebugMode
)

# Helper function for debug messages
function Write-DebugMessage {
    param ([string]$Message)
    if ($DebugMode) {
        Write-Host "DEBUG: $Message" -ForegroundColor Cyan
    }
}

# Check if the root path exists
if (-not (Test-Path -Path $Path -PathType Container)) {
    Write-Error "The specified path does not exist or is not a directory: $Path"
    return
}

# --- LONG PATH SUPPORT ---
$longPath = $Path
if ($longPath.StartsWith("\\")) {
    $longPath = "\\?\UNC\" + $longPath.Substring(2)
}
else {
    $longPath = "\\?\" + $Path
}

Write-Host "Starting duplicate file search in '$Path'..."
if ($ReportOnly) {
    Write-Host "MODE: Report Only. No files will be deleted." -ForegroundColor Green
}
Write-Host "Log/Report file will be saved to '$LogFilePath'"
if (-not $ReportOnly) {
    Write-Host "Using a size tolerance of $SizeToleranceBytes bytes for deletion."
    Write-Host "Deletion preference set to delete the '$Delete' file."
}
if ($DebugMode) { Write-Host "DEBUG MODE ENABLED" -ForegroundColor Yellow }
Write-DebugMessage "Resolved path for long file name support: '$longPath'"
Write-Host "Gathering list of directories to process..."

try {
    $rootDirectory = Get-Item -LiteralPath $longPath
    $subDirectories = Get-ChildItem -LiteralPath $longPath -Recurse -Directory -ErrorAction Stop
    $directoriesToProcess = @($rootDirectory) + $subDirectories
}
catch {
    Write-Error "Failed to access or read directories in the path '$Path'. Please check permissions."
    Write-Error "Error details: $($_.Exception.Message)"
    return
}

$totalDirs = $directoriesToProcess.Count
$currentDir = 0
Write-Host "Found $totalDirs directories to analyze."

foreach ($directory in $directoriesToProcess) {
    $currentDir++
    Write-Host "Processing directory $currentDir of $totalDirs : $($directory.PSChildName)"

    $files = @(Get-ChildItem -LiteralPath $directory.FullName -File -ErrorAction SilentlyContinue)
    $duplicatesToProcess = [System.Collections.Generic.List[PSCustomObject]]::new()
    
    if ($files.Count -lt 2) {
        Write-DebugMessage "Skipping directory, contains fewer than 2 files."
        continue
    }

    # Use nested loops to compare every unique pair of files
    for ($i = 0; $i -lt $files.Count; $i++) {
        $fileA = $files[$i]

        for ($j = $i + 1; $j -lt $files.Count; $j++) {
            $fileB = $files[$j]
            
            $originalFile, $duplicateFile = $null, $null

            if ($fileA.Extension -ne $fileB.Extension) {
                continue
            }

            if ($fileA.BaseName.Length -lt $fileB.BaseName.Length) {
                $originalFile = $fileA; $duplicateFile = $fileB
            }
            elseif ($fileB.BaseName.Length -lt $fileA.BaseName.Length) {
                $originalFile = $fileB; $duplicateFile = $fileA
            }
            else {
                continue
            }

            $baseOriginal = $originalFile.BaseName
            $baseDuplicate = $duplicateFile.BaseName
            $cleanOriginal = $baseOriginal -replace '\s\(\d+\)$'
            $cleanDuplicate = $baseDuplicate -replace '\s\(\d+\)$'

            $isDuplicate = $false
            if ($cleanOriginal -eq $cleanDuplicate) {
                $isDuplicate = $true
                Write-DebugMessage "Potential match (Simple): '$($originalFile.Name)' and '$($duplicateFile.Name)'"
            }
            elseif ($baseDuplicate.StartsWith($baseOriginal, [System.StringComparison]::OrdinalIgnoreCase)) {
                $isDuplicate = $true
                Write-DebugMessage "Potential match (Advanced): '$($originalFile.Name)' and '$($duplicateFile.Name)'"
            }

            if ($isDuplicate) {
                # In either mode, we queue the item. The decision to act is made later.
                $duplicatesToProcess.Add([PSCustomObject]@{
                    File1 = $originalFile
                    File2 = $duplicateFile
                })
            }
        }
    }

    # Process all the potential duplicates found in this directory
    foreach ($item in $duplicatesToProcess) {
        try {
            $sizeDifference = [math]::Abs($item.File1.Length - $item.File2.Length)

            if ($ReportOnly) {
                $friendlyDirectory = $item.File1.DirectoryName.Replace("\\?\UNC\", "\\").Replace("\\?\", "")
                
                # In report mode, 'Original' is the shorter name, 'Duplicate' is the longer.
                $logEntry = [PSCustomObject]@{
                    Timestamp            = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    Directory            = $friendlyDirectory
                    OriginalFile         = $item.File1.Name
                    OriginalFileSizeKB   = [math]::Round($item.File1.Length / 1KB, 2)
                    DuplicateFile        = $item.File2.Name
                    DuplicateFileSizeKB  = [math]::Round($item.File2.Length / 1KB, 2)
                    SizeDifferenceBytes  = $sizeDifference
                    ActionTaken          = "REPORTED"
                }
                $logEntry | Export-Csv -Path $LogFilePath -Append -NoTypeInformation -Encoding UTF8
                
                # Use a variable to simplify the Write-Host call and prevent parsing errors
                $friendlyReportPath = $item.File2.FullName.Replace("\\?\UNC\", "\\").Replace("\\?\", "")
                Write-Host "Reported: $friendlyReportPath" -ForegroundColor Green
            }
            else {
                # In deletion mode, check size tolerance first
                if ($sizeDifference -le $SizeToleranceBytes) {
                    Write-DebugMessage "--> SIZE MATCH (Difference: $sizeDifference bytes). Evaluating which file to delete."

                    # Determine the smaller and larger file first
                    $smallerFile, $largerFile = if ($item.File1.Length -lt $item.File2.Length) {
                        $item.File1, $item.File2
                    } else {
                        $item.File2, $item.File1
                    }

                    # Assign fileToKeep and fileToDelete based on the -Delete parameter
                    $fileToDelete, $fileToKeep = if ($Delete -eq 'Smaller') {
                        $smallerFile, $largerFile
                    } else { # $Delete is 'Larger'
                        $largerFile, $smallerFile
                    }
                    
                    $friendlyDirectory = $fileToDelete.DirectoryName.Replace("\\?\UNC\", "\\").Replace("\\?\", "")
                    $friendlyPath = $fileToDelete.FullName.Replace("\\?\UNC\", "\\").Replace("\\?\", "")

                    $logEntry = [PSCustomObject]@{
                        Timestamp           = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                        Directory           = $friendlyDirectory
                        FileKept            = $fileToKeep.Name
                        FileDeleted         = $fileToDelete.Name
                        SizeDifferenceBytes = $sizeDifference
                        ActionTaken         = "DELETED"
                        Status              = "Success"
                    }

                    if ($PSCmdlet.ShouldProcess($fileToDelete.FullName, "Delete file (Preference: $Delete, Size diff: $sizeDifference bytes)")) {
                        Remove-Item -LiteralPath $fileToDelete.FullName -Force
                        Write-Host "Deleted: $friendlyPath" -ForegroundColor Red
                    } else {
                        $logEntry.ActionTaken = "SKIPPED (WhatIf)"
                        Write-Host "WhatIf: Would delete $friendlyPath" -ForegroundColor Yellow
                    }
                    $logEntry | Export-Csv -Path $LogFilePath -Append -NoTypeInformation -Encoding UTF8
                }
                else {
                    Write-DebugMessage "--> SIZE MISMATCH (Difference: $sizeDifference bytes). Skipping pair '$($item.File1.Name)' and '$($item.File2.Name)'."
                }
            }
        } catch {
             $fileInError = if ($item) { $item.File1.FullName } else { "UNKNOWN" }
             $friendlyErrorPath = $fileInError.Replace("\\?\UNC\", "\\").Replace("\\?\", "")
             $errorDirectory = if ($item) { $item.File1.DirectoryName.Replace("\\?\UNC\", "\\").Replace("\\?\", "") } else { "UNKNOWN" }
             Write-Error "An error occurred while processing a pair in '$errorDirectory': $($_.Exception.Message)"
             $errorLogEntry = [PSCustomObject]@{ Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; Directory = $errorDirectory; File1 = $item.File1.Name; File2 = $item.File2.Name; SizeDifferenceBytes = "N/A"; ActionTaken = "ERROR"; Status = "Failed: $($_.Exception.Message)" }
             $errorLogEntry | Export-Csv -Path $LogFilePath -Append -NoTypeInformation -Encoding UTF8
        }
    }
}

Write-Host "Duplicate file cleanup/report complete. See log at '$LogFilePath' for details."

