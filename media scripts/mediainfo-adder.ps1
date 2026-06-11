<#
.SYNOPSIS
    Renames media files to include technical details extracted using MediaInfo.exe.

.DESCRIPTION
    This script scans a directory for media files (e.g., .mp4, .mkv), uses the MediaInfo CLI 
    to extract technical specifications, and appends them to the filename.

    Example:
    'My Video.mp4' -> 'My Video [1080p AVC AAC 2.0].mp4'

    It will skip any files that already appear to have tags in the format '[...]'.

.PARAMETER MediaInfoPath
    The full path to the 'MediaInfo.exe' command-line tool.

.PARAMETER DirectoryPath
    The path to the folder containing the media files you want to process. 
    The script will search this folder and all its subfolders.

.PARAMETER Extensions
    An array of file extensions to process. The default is @("*.mp4", "*.mkv", "*.avi").

.EXAMPLE
    .\Rename-MediaFiles.ps1 -MediaInfoPath "C:\Tools\MediaInfo\MediaInfo.exe" -DirectoryPath "D:\Movies"

.EXAMPLE
    .\Rename-MediaFiles.ps1 -MediaInfoPath "C:\Tools\MediaInfo\MediaInfo.exe" -DirectoryPath "D:\TV Shows" -Extensions "*.mkv", "*.ts" -Verbose

.NOTES
    - Requires MediaInfo CLI: https://mediaarea.net/en/MediaInfo/Download/Windows
    - Files are renamed immediately when the script runs. To preview changes without
      renaming, add '-WhatIf' to the 'Rename-Item' call near the end of the script.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$MediaInfoPath,

    [Parameter(Mandatory = $true)]
    [string]$DirectoryPath,

    [string[]]$Extensions = @("*.mp4", "*.mkv", "*.avi")
)

# --- Validate Paths ---
# Ensure MediaInfo.exe exists at the provided path
if (-not (Test-Path -Path $MediaInfoPath -PathType Leaf)) {
    Write-Error "MediaInfo.exe not found. Please check the path: '$MediaInfoPath'"
    return
}

# Ensure the target directory exists
if (-not (Test-Path -Path $DirectoryPath -PathType Container)) {
    Write-Error "The specified directory does not exist: '$DirectoryPath'"
    return
}

# --- Find Files ---
Write-Host "Searching for media files in '$DirectoryPath'..."
$mediaFiles = Get-ChildItem -Path $DirectoryPath -Include $Extensions -Recurse

if ($null -eq $mediaFiles) {
    Write-Warning "No media files found with the specified extensions."
    return
}

Write-Host "Found $($mediaFiles.Count) files to process."

# --- Process Each File ---
foreach ($file in $mediaFiles) {
    Write-Verbose "Processing file: $($file.FullName)"

    # Check if the filename already contains tags in brackets
    if ($file.BaseName -match '\[.*\]$') {
        Write-Verbose "Skipping '$($file.Name)' because it already appears to be tagged."
        continue
    }

    # --- Execute MediaInfo and Capture Output ---
    try {
        # Execute MediaInfo.exe and store the output text in a variable
        $mediaInfoOutput = & $MediaInfoPath $file.FullName
    }
    catch {
        Write-Error "Failed to execute MediaInfo.exe for file '$($file.Name)'. Error: $_"
        continue
    }

    # --- Parse MediaInfo Output ---
    # Initialize variables to store extracted info for each file
    $videoHeight = $null
    $videoCodec = $null
    $audioCodec = $null
    $audioChannels = $null
    $currentSection = ""

    # Process the output line by line for better reliability
    foreach ($line in $mediaInfoOutput) {
        # Determine the current section (General, Video, Audio, etc.)
        if ($line -match '^(General|Video|Audio|Text|Menu)$') {
            $currentSection = $matches[1].Trim()
            continue
        }

        # Parse key-value pairs based on the current section
        switch ($currentSection) {
            'Video' {
                # Only capture the first video track's info
                if ($null -eq $videoHeight -and $line -match 'Height\s+:\s+(\d[\d\s]+)\s+pixels') {
                    $videoHeight = ($matches[1] -replace '\s') + "p"
                }
                if ($null -eq $videoCodec -and $line -match 'Format\s+:\s+([^\r\n]+)') {
                    $videoCodec = $matches[1].Trim()
                }
            }
            'Audio' {
                # Only capture the first audio track's info
                if ($null -eq $audioCodec -and $line -match 'Format\s+:\s+([^\r\n]+)') {
                    $audioCodec = $matches[1].Trim().Split(' ')[0] # Takes "AAC" from "AAC LC"
                }
                if ($null -eq $audioChannels -and $line -match 'Channel\(s\)\s+:\s+(\d+)') {
                    $audioChannels = switch ($matches[1]) {
                        '1' { '1.0' }
                        '2' { '2.0' }
                        '6' { '5.1' }
                        '8' { '7.1' }
                        default { "$($matches[1]).0" }
                    }
                }
            }
        }
    }

    # --- Construct New Filename and Rename ---
    # Create an array of the extracted tags, filtering out any that were not found
    $tags = @($videoHeight, $videoCodec, $audioCodec, $audioChannels) | Where-Object { $_ -ne $null }

    if ($tags.Count -gt 0) {
        # Format the tags into a string like "[1080p AVC AAC 2.0]"
        $tagString = "[{0}]" -f ($tags -join ' ')
        
        # Build the new name
        $newFileName = "$($file.BaseName) $tagString$($file.Extension)"
        $newFilePath = Join-Path -Path $file.DirectoryName -ChildPath $newFileName

        Write-Host "Plan: Rename '$($file.Name)' -> '$newFileName'"

        # --- RENAME COMMAND ---
        # To preview renames without applying them, add '-WhatIf' to the Rename-Item call below.
        try {
            Rename-Item -Path $file.FullName -NewName $newFileName -ErrorAction Stop
        }
        catch {
            Write-Error "Failed to rename file '$($file.Name)'. Error: $_"
        }
    }
    else {
        Write-Warning "Could not extract sufficient media information for '$($file.Name)'."
    }
}

Write-Host "Script finished."
