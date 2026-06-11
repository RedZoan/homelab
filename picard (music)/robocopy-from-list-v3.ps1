<#
.SYNOPSIS
    Copies folders listed in text files to a destination using Robocopy, one batch file per subdirectory.

.DESCRIPTION
    Reads all .txt files in a specified directory. Each .txt file is treated as a batch list of
    source folder paths to copy. For each list file, a matching subdirectory is created under the
    destination root (named after the .txt file's basename), and all listed folders are copied there.

    This is designed to work with the output of text-file-folder-sorter.ps1, which splits a master
    folder list into alphabetical batch files (A.txt, B.txt, etc.). Running this script against
    that output copies each alphabetical group into its own destination subfolder.

    Robocopy is used with /COPY:DAT and /DCOPY:T to preserve file data, attributes, and timestamps
    : important when migrating between systems or to a NAS.

.PARAMETER listFileDirectory
    The directory containing the .txt batch list files to process.

.PARAMETER sourceRoot
    The source root path. Used to calculate relative paths for each folder in the list files.
    Folders that don't start with this path are skipped.

.PARAMETER destinationRoot
    The root destination directory. Each batch list file gets its own subdirectory here.

.PARAMETER logFilePath
    Path for the Robocopy log file. Output is appended (/LOG+) so all batches are captured in one log.

.EXAMPLE
    .\robocopy-from-list-v3.ps1 `
        -listFileDirectory "C:\temp\batchlists" `
        -sourceRoot "\\server\share\music" `
        -destinationRoot "D:\Backup" `
        -logFilePath "D:\Backup\robocopy.log"

.NOTES
    - Requires Robocopy (included with Windows).
    - Pairs with text-file-folder-sorter.ps1, which generates the .txt batch list files.
    - /COPY:DAT preserves Data, Attributes, and Timestamps : recommended for cross-system copies.
    - /DCOPY:T preserves directory timestamps.
    - The log file is appended across all batches, giving one consolidated log for the full run.
#>

param(
    [Parameter(Mandatory=$true, HelpMessage="Enter the path to the DIRECTORY containing the .txt robocopy lists.")]
    [string]$listFileDirectory,

    [Parameter(Mandatory=$true, HelpMessage="Enter the source root path to be replaced.")]
    [string]$sourceRoot,

    [Parameter(Mandatory=$true, HelpMessage="Enter the destination directory.")]
    [string]$destinationRoot,

    [Parameter(Mandatory=$true, HelpMessage="Enter the path for the log file.")]
    [string]$logFilePath
)

# --- Script ---

# Check if the list file DIRECTORY exists
if (-not (Test-Path -Path $listFileDirectory -PathType Container)) {
    Write-Host "Error: The directory '$listFileDirectory' was not found." -ForegroundColor Red
    Read-Host -Prompt "Press Enter to exit"
    exit
}

# Get all .txt files in the specified directory
$listTxtFiles = Get-ChildItem -Path $listFileDirectory -Filter "*.txt"

if ($listTxtFiles.Count -eq 0) {
    Write-Host "No .txt files found in '$listFileDirectory'." -ForegroundColor Yellow
    exit
}

# --- Outer loop for each .txt file ---
foreach ($listFile in $listTxtFiles) {
    $subDirName = $listFile.BaseName
    $batchDestinationRoot = Join-Path -Path $destinationRoot -ChildPath $subDirName

    Write-Host "-----------------------------------------------------------------" -ForegroundColor Magenta
    Write-Host "Processing list file: $($listFile.Name)" -ForegroundColor Magenta
    Write-Host "Destination for this batch: $batchDestinationRoot" -ForegroundColor Magenta
    Write-Host "-----------------------------------------------------------------"

    # Read the folder paths from the current list file
    $foldersToCopy = Get-Content -Path $listFile.FullName

    Write-Host "Found $($foldersToCopy.Count) folders to process from $($listFile.Name)." -ForegroundColor Cyan
    Write-Host "Starting robocopy process. See log file for details: $logFilePath" -ForegroundColor Green

    # --- Inner loop for each folder path in the current list file ---
    foreach ($sourceFolder in $foldersToCopy) {
        try {
            # Skip empty lines that might be in the text file
            if (-not ([string]::IsNullOrWhiteSpace($sourceFolder))) {
                # Determine the destination path by replacing the source root with the destination root
                if ($sourceFolder.StartsWith($sourceRoot, [System.StringComparison]::InvariantCultureIgnoreCase)) {
                    $relativePath = $sourceFolder.Substring($sourceRoot.Length)
                    $destinationFolder = Join-Path -Path $batchDestinationRoot -ChildPath $relativePath
                    
                    Write-Host "Copying '$sourceFolder' to '$destinationFolder'..."

                    # Robocopy arguments
                    # /E :: copy subdirectories, including Empty ones.
                    # /COPY:DAT :: Copies Data, Attributes, Timestamps. This is best for Linux -> Windows copies.
                    # /DCOPY:T :: Copies Timestamps for directories.
                    # /R:1 /W:1 :: Retry once, wait 1 second.
                    # /TEE :: output to console and log file.
                    # /LOG+ :: Append the output to the log file.
                    $robocopyArgs = @(
                        "`"$sourceFolder`"",
                        "`"$destinationFolder`"",
                        "/E",
                        "/COPY:DAT",
                        "/DCOPY:T",
                        "/R:1",
                        "/W:1",
                        "/TEE",
                        "/LOG+:`"$logFilePath`""
                    )

                    # Start the robocopy process and wait for it to complete
                    Start-Process robocopy -ArgumentList $robocopyArgs -Wait -NoNewWindow
                }
                else {
                    Write-Host "Skipping '$sourceFolder' as it does not start with the provided source root '$sourceRoot'." -ForegroundColor Yellow
                }
            }
        }
        catch {
            Write-Host "An error occurred while processing '$sourceFolder':" -ForegroundColor Red
            Write-Host $_.Exception.Message -ForegroundColor Red
        }
    }
}

Write-Host "All robocopy processes completed." -ForegroundColor Green

