<#
.SYNOPSIS
    Recursively searches for and deletes duplicate files within the same directory.

.DESCRIPTION
    This script searches a specified root folder and all its subfolders to find duplicate files.
    A file is considered a duplicate if it resides in the same directory as an original file,
    shares the same file extension, has a name ending in " (1)", " (2)", etc., and has a file size
    that is within a specified tolerance of the original.

.PARAMETER Path
    The starting folder path to search recursively. This parameter is mandatory.

.PARAMETER LogFilePath
    The full path for the CSV log file that will be created or appended to. This parameter is mandatory.

.PARAMETER SizeToleranceBytes
    The maximum allowed difference in bytes between an original file and a duplicate for them to be
    considered a match. Defaults to 100 bytes.

.PARAMETER DebugMode
    A switch that, when present, enables highly verbose console output for troubleshooting.

.EXAMPLE
    # Perform a "dry run" using the default 100-byte size tolerance.
    .\delete_duplicates.ps1 -Path "C:\Music" -LogFilePath "C:\temp\log.csv" -WhatIf

.EXAMPLE
    # Delete duplicates using a larger size tolerance of 500 bytes.
    .\delete_duplicates.ps1 -Path "C:\Music" -LogFilePath "C:\temp\log.csv" -SizeToleranceBytes 500

.NOTES
    Version: 1.6
    - Added a -SizeToleranceBytes parameter (default 100) to handle cases where duplicate files
      have very small differences in file size due to metadata.
    - The core comparison logic now checks if the size difference is within this tolerance instead
      of requiring an exact match.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter the root path to search for duplicate files.")]
    [string]$Path,

    [Parameter(Mandatory = $true, HelpMessage = "Enter the path for the log file (e.g., C:\temp\deletion_log.csv).")]
    [string]$LogFilePath,

    [Parameter(Mandatory = $false, HelpMessage = "The maximum allowed size difference in bytes. Defaults to 100.")]
    [int]$SizeToleranceBytes = 100,

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
if (-not (Test-Path -Path $Path)) {
    Write-Error "The specified path does not exist: $Path"
    return
}

Write-Host "Starting duplicate file search in '$Path'..."
Write-Host "Log file will be saved to '$LogFilePath'"
Write-Host "Using a size tolerance of $SizeToleranceBytes bytes."
if ($DebugMode) { Write-Host "DEBUG MODE ENABLED" -ForegroundColor Yellow }
Write-Host "Gathering list of directories to process..."

try {
    $rootDirectory = Get-Item -Path $Path
    $subDirectories = Get-ChildItem -Path $Path -Recurse -Directory -ErrorAction Stop
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
    Write-Host "Processing directory $currentDir of $totalDirs : $($directory.FullName)"

    $filesInDir = Get-ChildItem -Path $directory.FullName -File -ErrorAction SilentlyContinue
    $filesByBaseName = $filesInDir | Group-Object { $_.Name -replace '\s\(\d+\)(?=\.[^.]+$)' }

    foreach ($baseNameGroup in $filesByBaseName) {
        Write-DebugMessage "Analyzing base name group: '$($baseNameGroup.Name)' with $($baseNameGroup.Count) file(s)."
        
        if ($baseNameGroup.Count -gt 1) {
            Write-DebugMessage "Found potential duplicates for '$($baseNameGroup.Name)'."
            $duplicatePattern = '\s\(\d+\)(?=\.[^.]+$)'
            $originals = @($baseNameGroup.Group | Where-Object { $_.Name -notmatch $duplicatePattern })
            Write-DebugMessage "Found $($originals.Count) possible 'original' file(s) for this group."

            if ($originals.Count -eq 1) {
                $originalFile = $originals[0]
                Write-DebugMessage "Identified original file: '$($originalFile.Name)' (Size: $($originalFile.Length) bytes)."
                
                $duplicateFiles = $baseNameGroup.Group | Where-Object { $_.FullName -ne $originalFile.FullName }

                foreach ($duplicateFile in $duplicateFiles) {
                    Write-DebugMessage "--> Checking candidate: '$($duplicateFile.Name)' (Size: $($duplicateFile.Length) bytes)."
                    try {
                        # NEW LOGIC: Check if the absolute difference in size is within the tolerance
                        $sizeDifference = [math]::Abs($originalFile.Length - $duplicateFile.Length)
                        if ($sizeDifference -le $SizeToleranceBytes) {
                            Write-DebugMessage "--> SIZE MATCH (Difference: $sizeDifference bytes). Preparing to delete '$($duplicateFile.Name)'."
                            $logEntry = [PSCustomObject]@{
                                Timestamp      = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                                Directory      = $duplicateFile.DirectoryName
                                OriginalFile   = $originalFile.Name
                                DuplicateFile  = $duplicateFile.Name
                                SizeDifference = $sizeDifference
                                ActionTaken    = "DELETED"
                                Status         = "Success"
                            }

                            if ($PSCmdlet.ShouldProcess($duplicateFile.FullName, "Delete duplicate file (Size diff: $sizeDifference bytes)")) {
                                Remove-Item -LiteralPath $duplicateFile.FullName -Force
                                Write-Host "Deleted: $($duplicateFile.FullName)" -ForegroundColor Red
                            } else {
                                $logEntry.ActionTaken = "SKIPPED (WhatIf)"
                                Write-Host "WhatIf: Would delete $($duplicateFile.FullName)" -ForegroundColor Yellow
                            }
                            $logEntry | Export-Csv -Path $LogFilePath -Append -NoTypeInformation -Encoding UTF8
                        } else {
                            Write-DebugMessage "--> SIZE MISMATCH (Difference: $sizeDifference bytes). Skipping '$($duplicateFile.Name)'."
                        }
                    } catch {
                        Write-Error "An error occurred while processing '$($duplicateFile.FullName)': $($_.Exception.Message)"
                        $errorLogEntry = [PSCustomObject]@{ Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; Directory = $duplicateFile.DirectoryName; OriginalFile = $originalFile.Name; DuplicateFile = $duplicateFile.Name; SizeDifference = "N/A"; ActionTaken = "ERROR"; Status = "Failed: $($_.Exception.Message)" }
                        $errorLogEntry | Export-Csv -Path $LogFilePath -Append -NoTypeInformation -Encoding UTF8
                    }
                }
            } else {
                 Write-Warning "Skipping file group based on '$($baseNameGroup.Name)' in directory '$($directory.FullName)' because an unambiguous original file could not be determined. Found $($originals.Count) candidates."
            }
        }
    }
}

Write-Host "Duplicate file cleanup complete. See log at '$LogFilePath' for details."

