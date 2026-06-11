<#
.SYNOPSIS
Moves .mp4 files from a source directory to individual subfolders in a destination directory.
Each subfolder is named after the base name of the video file.

.DESCRIPTION
This script iterates through all .mp4 files in the specified source directory.
For each file, it creates a corresponding folder in the destination directory (if it doesn't already exist)
and then moves the file into that folder.
It includes error handling and verbose output to help diagnose issues.
This version uses -LiteralPath with Test-Path to handle special characters in filenames.

.PARAMETER SourceDirectory
The full path to the directory containing the .mp4 files to be processed.
Example: "\\networkshare\source_videos" or "C:\MyVideos\ToBeProcessed"

.PARAMETER DestinationBaseDirectory
The full path to the base directory where the processed video folders will be created.
Example: "\\networkshare\processed_videos" or "C:\MyVideos\Processed"

.EXAMPLE
# Ensure you have PowerShell 7+ for simplified parameter splatting if you copy-paste this example directly.
# Otherwise, call like this:
# .\YourScriptName.ps1 -SourceDirectory "\\networkshare\videos" -DestinationBaseDirectory "\\networkshare\processed_videos"

$scriptParams = @{
    SourceDirectory          = "\\networkshare\videos" # Replace with your actual source path
    DestinationBaseDirectory = "\\networkshare\processed_videos" # Replace with your actual destination path
}
# .\ThisScript.ps1 @scriptParams
# This example shows how to call it after saving the script to a .ps1 file.
# You would replace "\\networkshare\videos" and "\\networkshare\processed_videos" with your actual paths.

.NOTES
- Save this script as a .ps1 file (e.g., Organize-Videos.ps1).
- Run it from a PowerShell console that has access to the network shares.
- Ensure the account running the script has:
  - Read permissions for the SourceDirectory.
  - Read, Write, and Delete permissions for the DestinationBaseDirectory and its subfolders.
  - Delete permissions for files in the SourceDirectory (as Move-Item deletes the source after a successful copy).
- If a video file is locked by another process (e.g., open in a media player), Move-Item may fail for that file.
- The script checks if the target file already exists in the destination subfolder and skips it to prevent accidental overwrites.
  You can modify this behavior if needed (e.g., to add -Force or rename).
#>
param (
    [Parameter(Mandatory=$true)]
    [string]$SourceDirectory,

    [Parameter(Mandatory=$true)]
    [string]$DestinationBaseDirectory
)

# --- Script Start ---
Write-Host "Starting video processing script..." -ForegroundColor Green
Write-Host "Source Directory: $SourceDirectory"
Write-Host "Destination Base Directory: $DestinationBaseDirectory"
Write-Host "--------------------------------------------------"

# Validate paths (basic check if they are actual directories)
# Using -LiteralPath for Test-Path and then checking PSIsContainer for directory validation
if (!(Test-Path -LiteralPath $SourceDirectory) -or !((Get-Item -LiteralPath $SourceDirectory -ErrorAction SilentlyContinue).PSIsContainer)) {
    Write-Error "FATAL: Source directory '$SourceDirectory' does not exist or is not a folder."
    Write-Error "Please check the path and permissions. Script will exit."
    exit 1
}

# Ensure the base destination directory exists, try to create if not
if (!(Test-Path -LiteralPath $DestinationBaseDirectory) -or !((Get-Item -LiteralPath $DestinationBaseDirectory -ErrorAction SilentlyContinue).PSIsContainer)) {
    Write-Host "Destination base directory '$DestinationBaseDirectory' does not exist or is not a folder. Attempting to create it..."
    try {
        # New-Item will fail if $DestinationBaseDirectory is an existing file, which is desired behavior.
        New-Item -ItemType Directory -Path $DestinationBaseDirectory -ErrorAction Stop # Using -Path here as New-Item handles literal paths by default.
        Write-Host "Successfully created destination base directory: $DestinationBaseDirectory" -ForegroundColor Green
    } catch {
        Write-Error "FATAL: Failed to create destination base directory '$DestinationBaseDirectory'. Error: $($_.Exception.Message)"
        Write-Error "Please check permissions and path validity. Script will exit."
        exit 1
    }
} else {
    Write-Host "Destination base directory '$DestinationBaseDirectory' already exists and is a folder."
}

# Get the .mp4 files
Write-Host "Searching for .mp4 files in '$SourceDirectory'..."
$filesToProcess = Get-ChildItem -Path $SourceDirectory -File -Filter "*.mp4" -ErrorAction SilentlyContinue

if ($null -eq $filesToProcess -or $filesToProcess.Count -eq 0) {
    Write-Warning "No .mp4 files found in '$SourceDirectory' or the directory is inaccessible."
    Write-Host "Script finished."
    exit 0 # Exit gracefully if no files to process
}

Write-Host "Found $($filesToProcess.Count) .mp4 file(s) to process."

# Process each file
foreach ($file in $filesToProcess) {
    # Use the filename (without extension) as the subfolder name, then build the full destination path.
    $folderName = $file.BaseName
    $fullFolderPath = Join-Path -Path $DestinationBaseDirectory -ChildPath $folderName

    Write-Host "" # Newline for readability per file
    Write-Host "Processing file: $($file.FullName)" -ForegroundColor Cyan
    Write-Host "  Target folder name: $folderName"
    Write-Host "  Target full folder path: $fullFolderPath"

    # Create the destination subfolder if it doesn't already exist.
    # If something exists at that path but is a file (not a folder), skip this video to avoid a conflict.
    if (!(Test-Path -LiteralPath $fullFolderPath) -or !((Get-Item -LiteralPath $fullFolderPath -ErrorAction SilentlyContinue).PSIsContainer)) {
        # Check if it's a file, if so, report and skip.
        if ((Test-Path -LiteralPath $fullFolderPath) -and !((Get-Item -LiteralPath $fullFolderPath -ErrorAction SilentlyContinue).PSIsContainer)) {
            Write-Error "  ERROR: A FILE named '$fullFolderPath' already exists. Cannot create a directory with the same name."
            Write-Warning "  Skipping file '$($file.FullName)' due to conflicting file name for target folder."
            Write-Host "--------------------------------------------------"
            continue # Skip to the next file
        }
        
        Write-Host "  Creating folder: $fullFolderPath"
        try {
            New-Item -ItemType Directory -Path $fullFolderPath -ErrorAction Stop
            Write-Host "  Successfully created folder: $fullFolderPath" -ForegroundColor Green
        } catch {
            Write-Error "  ERROR: Failed to create folder '$fullFolderPath'. Error: $($_.Exception.Message)"
            Write-Warning "  Skipping file '$($file.FullName)' due to folder creation error."
            Write-Host "--------------------------------------------------"
            continue # Skip to the next file
        }
    } else {
        Write-Host "  Folder '$fullFolderPath' already exists and is a directory."
    }

    # Define the potential full path of the file in its new destination folder
    $destinationFilePath = Join-Path -Path $fullFolderPath -ChildPath $file.Name

    # Check if the file already exists in the destination folder using -LiteralPath
    if (Test-Path -LiteralPath $destinationFilePath) {
        Write-Warning "  WARNING: A file named '$($file.Name)' already exists in '$fullFolderPath'."
        Write-Warning "  Skipping move for '$($file.FullName)' to prevent overwrite."
        Write-Warning "  To enable overwriting, you could add '-Force' to Move-Item and remove this check."
        Write-Host "--------------------------------------------------"
        continue # Skip to the next file
    }

    # Attempt to move the file
    Write-Host "  Attempting to move '$($file.FullName)' into folder '$fullFolderPath'..."
    try {
        Move-Item -LiteralPath $file.FullName -Destination $fullFolderPath -ErrorAction Stop -Verbose
        Write-Host "  SUCCESS: Moved '$($file.FullName)' to '$fullFolderPath\$($file.Name)'" -ForegroundColor Green
    } catch {
        Write-Error "  ERROR: Failed to move file '$($file.FullName)' to '$fullFolderPath'."
        Write-Error "  Error details: $($_.Exception.Message)"
        
        # Diagnostics to help identify the root cause of the failure
        Write-Warning "  Troubleshooting tips:"
        Write-Warning "  - Is the file '$($file.Name)' locked by another application (e.g., media player, antivirus)?"
        Write-Warning "  - Does the account running the script have WRITE permissions to '$fullFolderPath'?"
        Write-Warning "  - Does the account running the script have DELETE permissions for '$($file.FullName)' in '$($file.DirectoryName)'?"
        if (!(Test-Path -LiteralPath $file.FullName)) {
            Write-Warning "  DIAGNOSTIC: Source file no longer exists — the move may have partially succeeded."
        } else {
            Write-Warning "  DIAGNOSTIC: Source file still exists at the original location."
        }
        if (Test-Path -LiteralPath $destinationFilePath) {
            Write-Warning "  DIAGNOSTIC: File exists at destination — the copy succeeded but source deletion may have failed."
        } else {
            Write-Warning "  DIAGNOSTIC: File does not exist at destination — the copy did not complete."
        }
    }
    Write-Host "--------------------------------------------------"
}

Write-Host "Script finished." -ForegroundColor Green
