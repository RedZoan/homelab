<#
.SYNOPSIS
    Combines media files within each subdirectory using FFmpeg, outputting one merged file per folder.

.DESCRIPTION
    Recursively scans a root directory for subdirectories containing media files.
    Any subdirectory with two or more media files is processed: FFmpeg concatenates them
    in alphabetical order into a single output file, which is saved to the script's own directory.
    The output filename is prefixed with the subdirectory name for easy identification.

    Requires FFmpeg. Either set the $customFFmpegPath variable to your FFmpeg executable,
    or ensure 'ffmpeg' is available on your system PATH.

.PARAMETER RootDirectoryToSearch
    The root folder to scan for subdirectories containing media files.
    Defaults to the current working directory if not specified.

.EXAMPLE
    .\combine-recursive-v2.ps1
    Processes subdirectories under the current directory.

.EXAMPLE
    .\combine-recursive-v2.ps1 -RootDirectoryToSearch "D:\Videos\Raw"
    Processes subdirectories under D:\Videos\Raw.

.NOTES
    - Requires FFmpeg (https://ffmpeg.org/download.html).
    - Files are concatenated using FFmpeg's concat demuxer (-c copy), so no re-encoding occurs.
    - A temporary 'mylist.txt' file is created in each processed subdirectory during the run.
      Uncomment the cleanup line near the end of the script to auto-delete it afterward.
    - Subdirectories with fewer than two media files are skipped.
#>
param(
    [string]$RootDirectoryToSearch = ""
)

# --- Configuration ---
$listFile = "mylist.txt" # Name of the list file, created in each relevant subdirectory
$mediaExtensions = @("*.mp4", "*.mkv", "*.avi", "*.mov", "*.ts", "*.webm", "*.flv", "*.wmv")

# OPTIONAL: Set this to the full path of ffmpeg.exe if it is not in your system PATH.
# Leave as "" to search your PATH automatically.
# Example: $customFFmpegPath = "C:\Tools\ffmpeg\bin\ffmpeg.exe"
$customFFmpegPath = ""

# --- Helper function to sanitize names for use in filenames ---
function Sanitize-FileNamePart {
    param (
        [string]$Name
    )
    # Replace invalid file name characters with an underscore.
    # Invalid characters: \ / : * ? " < > |
    # Also, replace multiple spaces/underscores with a single underscore and trim.
    $sanitized = $Name -replace '[\\/:*?"<>|]', '_' -replace '\s+', '_' -replace '_+', '_'
    return $sanitized.Trim('_')
}

# --- Determine Effective Root Directory for Processing ---
$effectiveProcessRoot = ""
if (-not [string]::IsNullOrEmpty($RootDirectoryToSearch)) {
    if (Test-Path -Path $RootDirectoryToSearch -PathType Container) {
        $effectiveProcessRoot = (Resolve-Path -Path $RootDirectoryToSearch).Path
        Write-Host "Using specified RootDirectoryToSearch: $effectiveProcessRoot"
    } else {
        Write-Error "The provided RootDirectoryToSearch '$RootDirectoryToSearch' is not a valid directory or is inaccessible."
        Read-Host "Press Enter to exit."
        exit 1
    }
} else {
    $effectiveProcessRoot = (Resolve-Path -Path .).Path # Default to current working directory
    Write-Host "No RootDirectoryToSearch provided. Using current working directory as processing root: $effectiveProcessRoot"
}

# --- Define the Output Directory for Combined Files (Script's Location) ---
$scriptOutputDirectory = $PSScriptRoot
Write-Host "Combined video files will be saved to the script's directory: $scriptOutputDirectory"
if (-not (Test-Path -Path $scriptOutputDirectory -PathType Container)) {
    Write-Warning "The script's directory '$scriptOutputDirectory' seems invalid or inaccessible. Output might fail."
    # Optionally, create it if it doesn't exist, though $PSScriptRoot should always exist if the script is running.
    # try { New-Item -ItemType Directory -Path $scriptOutputDirectory -ErrorAction Stop | Out-Null } catch {}
}


# --- Determine FFmpeg Executable ---
$ffmpegExecutableToUse = ""
if (-not [string]::IsNullOrEmpty($customFFmpegPath)) {
    Write-Host "Attempting to use custom FFmpeg path: $customFFmpegPath"
    if (Test-Path -Path $customFFmpegPath -PathType Leaf) {
        $ffmpegExecutableToUse = (Resolve-Path -Path $customFFmpegPath).Path
        Write-Host "Successfully located custom FFmpeg: $ffmpegExecutableToUse"
    } else {
        Write-Error "Custom FFmpeg path specified but NOT FOUND: $customFFmpegPath"; Read-Host "Press Enter to exit."; exit 1
    }
} else {
    Write-Host "No custom FFmpeg path specified. Searching in system PATH..."
    $ffmpegInPath = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($ffmpegInPath) {
        $ffmpegExecutableToUse = $ffmpegInPath.Source
        Write-Host "FFmpeg found in PATH: $ffmpegExecutableToUse"
    } else {
        Write-Error "FFmpeg not found in system PATH and no custom path was specified."; Read-Host "Press Enter to exit."; exit 1
    }
}

# --- Get All Directories to Process (Root + Subdirectories) ---
$directoriesToProcess = @()
try {
    $directoriesToProcess += Get-Item -LiteralPath $effectiveProcessRoot # Add the root itself
    $subDirectories = Get-ChildItem -LiteralPath $effectiveProcessRoot -Recurse -Directory -ErrorAction Stop
    if ($null -ne $subDirectories) {
        $directoriesToProcess += $subDirectories
    }
}
catch {
    Write-Error "Error getting list of directories under '$effectiveProcessRoot'. Details: $($_.Exception.Message)"
    Read-Host "Press Enter to exit."
    exit 1
}

Write-Host "Found $($directoriesToProcess.Count) director(y/ies) to check for media files."

# --- Process Each Directory ---
$overallSuccessCount = 0
$overallFailCount = 0

foreach ($dirInfo in $directoriesToProcess) {
    $currentDirPath = $dirInfo.FullName
    $currentDirName = $dirInfo.Name # Name of the subdirectory being processed
    Write-Host ("-" * 70)
    Write-Host "Processing directory: $currentDirPath"

    $mediaFilesInThisDir = @()
    try {
        # Find media files directly in the current directory (not its sub-subdirectories)
        $filesInCurrentSubDir = Get-ChildItem -LiteralPath $currentDirPath -File -ErrorAction Stop
        
        if ($null -ne $filesInCurrentSubDir) {
            foreach ($fileItem in $filesInCurrentSubDir) {
                foreach ($extensionPattern in $mediaExtensions) {
                    if ($fileItem.Name -like $extensionPattern) {
                        $mediaFilesInThisDir += $fileItem
                        break # Matched this file, move to next file
                    }
                }
            }
        }
    }
    catch {
        Write-Warning "Could not access or list files in '$currentDirPath'. Skipping. Details: $($_.Exception.Message)"
        continue # Move to the next directory
    }

    # Need at least two files to combine
    if ($mediaFilesInThisDir.Count -lt 2) {
        Write-Host "Fewer than two media files found directly in '$currentDirPath' with specified extensions. Skipping combination for this directory."
        continue
    }

    Write-Host "Found $($mediaFilesInThisDir.Count) media file(s) in '$currentDirPath':"
    $mediaFilesInThisDir | ForEach-Object { Write-Host "  - $($_.Name)" }

    # --- Create FFmpeg Input List File (in the current subdirectory) ---
    $listFilePathInSubDir = Join-Path $currentDirPath $listFile
    Write-Host "Creating FFmpeg input file: $listFilePathInSubDir"
    try {
        $fileContentLines = @()
        foreach ($file in $mediaFilesInThisDir) {
            # For mylist.txt in the same directory, paths should be relative (just the filename)
            $escapedFileName = $file.Name -replace "'", "'\''" 
            $fileContentLines += "file '$($escapedFileName)'"
        }
        [System.IO.File]::WriteAllLines($listFilePathInSubDir, $fileContentLines)
        Write-Host "$listFile created successfully in '$currentDirPath'."
    }
    catch {
        Write-Error "Error creating list file '$listFile' in '$currentDirPath'. Details: $($_.Exception.Message)"
        $overallFailCount++
        continue # Skip to next directory
    }

    # --- Determine Output File Name and Path (in Script's Directory) ---
    $firstFileBaseNameInSubDir = $mediaFilesInThisDir[0].BaseName
    $sanitizedSubDirName = Sanitize-FileNamePart -Name $currentDirName
    
    # Determine the output filename prefix from the subdirectory name.
    # Falls back to "root" if the current directory is also the script output directory
    # (to avoid a blank or self-referential prefix), and to "combined" as a last resort.
    $outputFileNamePrefix = $sanitizedSubDirName
    if ([string]::IsNullOrWhiteSpace($outputFileNamePrefix) -or $currentDirPath -eq $scriptOutputDirectory) {
        $outputFileNamePrefix = "root"
    }
    if ([string]::IsNullOrWhiteSpace($outputFileNamePrefix)) {
        $outputFileNamePrefix = "combined"
    }


    $outputFileNameInScriptDir = "${outputFileNamePrefix}_${firstFileBaseNameInSubDir}_combined.mp4"
    $outputFilePathInScriptDir = Join-Path $scriptOutputDirectory $outputFileNameInScriptDir

    Write-Host "Attempting to combine media files into: $outputFilePathInScriptDir"

    $quotedListFilePathForCmd = "`"$listFilePathInSubDir`""       # Full path to mylist.txt (in subdirectory)
    $quotedOutputFilePathForCmd = "`"$outputFilePathInScriptDir`"" # Full path for output (in script's directory)

    $ffmpegArgs = "-f concat -safe 0 -i $quotedListFilePathForCmd -c copy $quotedOutputFilePathForCmd"
    
    Write-Host "Running FFmpeg command: `"$ffmpegExecutableToUse`" $ffmpegArgs"
    Write-Host "FFmpeg Working Directory will be: $currentDirPath" # Subdirectory being processed

    try {
        # Set WorkingDirectory for FFmpeg to the current subdirectory.
        # This is crucial for FFmpeg to resolve relative paths in mylist.txt.
        $process = Start-Process -FilePath $ffmpegExecutableToUse -ArgumentList $ffmpegArgs -WorkingDirectory $currentDirPath -Wait -NoNewWindow -PassThru
        
        if ($process.ExitCode -ne 0) {
            Write-Error "FFmpeg failed for files from '$currentDirPath' (Exit code $($process.ExitCode)). Output was intended for '$outputFilePathInScriptDir'."
            $overallFailCount++
        }
        elseif (Test-Path -LiteralPath $outputFilePathInScriptDir) {
            Write-Host "✅ Success! Combined media file created: $outputFilePathInScriptDir" -ForegroundColor Green
            $overallSuccessCount++
        }
        else {
            Write-Warning "FFmpeg command for files from '$currentDirPath' executed (Exit Code: $($process.ExitCode)), but the output file '$outputFilePathInScriptDir' was not found."
            $overallFailCount++
        }
    }
    catch {
        Write-Error "Error running FFmpeg for directory '$currentDirPath'. Details: $($_.Exception.Message)"
        $overallFailCount++
    }

    # --- Optional: Clean up the list file for this subdirectory ---
    # try { Remove-Item -LiteralPath $listFilePathInSubDir -Force -ErrorAction SilentlyContinue } catch {}
}

Write-Host ("-" * 70)
Write-Host "Script finished processing all directories."
Write-Host "Combined files saved to: $scriptOutputDirectory"
Write-Host "Successful combinations: $overallSuccessCount"
Write-Host "Failed/Skipped combinations: $overallFailCount"
Read-Host "Press Enter to exit."
