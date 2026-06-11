<#
.SYNOPSIS
    This script moves folders based on a user-defined regex pattern.
    It prompts for source and destination root folders,
    allows selection of 'tmdb' or 'tvdb' patterns,
    and enables matching or not matching the pattern.

.DESCRIPTION
    The script first asks the user to input a source and a destination
    directory. Then, it prompts the user to choose between 'tmdb' or 'tvdb'
    which are used to construct a regular expression pattern for folder names.
    Finally, it asks if folders matching the pattern should be moved, or if
    folders NOT matching the pattern should be moved. It then iterates
    through all direct subfolders in the source directory and moves them
    to the destination based on the selected criteria.

.PARAMETER SourceRootFolder
    The root directory from which folders will be searched and moved.

.PARAMETER DestinationRootFolder
    The root directory to which matching/non-matching folders will be moved.

.EXAMPLE
    .\Move-FoldersByPattern.ps1
    (Running the script will prompt for all necessary inputs.)

.NOTES
    Version: 1.0
#>

function Move-FoldersByPattern {
    [CmdletBinding()]
    Param()

    # --- Step 1: Get Source Root Folder ---
    $SourceRootFolder = Read-Host "Enter the SOURCE root folder path (e.g., C:\Downloads)"
    while (-not (Test-Path -Path $SourceRootFolder -PathType Container)) {
        Write-Warning "Source folder '$SourceRootFolder' does not exist or is not a directory. Please enter a valid path."
        $SourceRootFolder = Read-Host "Enter the SOURCE root folder path"
    }
    Write-Host "Source folder set to: $SourceRootFolder"

    # --- Step 2: Get Destination Root Folder ---
    $DestinationRootFolder = Read-Host "Enter the DESTINATION root folder path (e.g., C:\Movies)"
    while (-not (Test-Path -Path $DestinationRootFolder -PathType Container)) {
        Write-Warning "Destination folder '$DestinationRootFolder' does not exist or is not a directory. Creating it..."
        try {
            New-Item -Path $DestinationRootFolder -ItemType Directory -Force | Out-Null
            Write-Host "Destination folder created: $DestinationRootFolder"
        }
        catch {
            Write-Error "Failed to create destination folder: $_. Please ensure you have write permissions."
            return # Exit if we can't create the destination
        }
    }
    Write-Host "Destination folder set to: $DestinationRootFolder"

    # --- Step 3: Select Search String Type ---
    $SearchTypeOptions = "tmdb", "tvdb"
    $SelectedSearchType = Read-Host "Select search type ('tmdb' or 'tvdb')"
    while ($SelectedSearchType -notin $SearchTypeOptions) {
        Write-Warning "Invalid selection. Please enter 'tmdb' or 'tvdb'."
        $SelectedSearchType = Read-Host "Select search type ('tmdb' or 'tvdb')"
    }

    # Construct the REGEX pattern based on user selection
    # The pattern matches "{searchType-d[1-10 digits]}"
    $RegexPattern = "{${SelectedSearchType}-\d{1,10}}"
    Write-Host "Folders will be searched for the pattern: '$RegexPattern'"

    # --- Step 4: Choose Match or Do Not Match ---
    $MatchOptionOptions = "match", "not match"
    $SelectedMatchOption = Read-Host "Do you want to move folders that 'match' or 'not match' the pattern?"
    while ($SelectedMatchOption -notin $MatchOptionOptions) {
        Write-Warning "Invalid selection. Please enter 'match' or 'not match'."
        $SelectedMatchOption = Read-Host "Do you want to move folders that 'match' or 'not match' the pattern?"
    }

    Write-Host "Searching for folders in: $SourceRootFolder"
    Write-Host "Moving selected folders to: $DestinationRootFolder"

    # --- Step 5: Process Folders ---
    $FoldersMovedCount = 0
    $FoldersSkippedCount = 0

    try {
        # Get all direct subdirectories in the source folder
        Get-ChildItem -Path $SourceRootFolder -Directory | ForEach-Object {
            $FolderName = $_.Name
            $FolderPath = $_.FullName
            $DestinationPath = Join-Path -Path $DestinationRootFolder -ChildPath $FolderName

            $MatchesPattern = $FolderName -match $RegexPattern

            $ShouldMove = $false

            if ($SelectedMatchOption -eq "match" -and $MatchesPattern) {
                $ShouldMove = $true
            } elseif ($SelectedMatchOption -eq "not match" -and -not $MatchesPattern) {
                $ShouldMove = $true
            }

            if ($ShouldMove) {
                Write-Host "Attempting to move folder: '$FolderName'..."
                try {
                    Move-Item -Path $FolderPath -Destination $DestinationRootFolder -Force -ErrorAction Stop
                    Write-Host "Successfully moved '$FolderName' to '$DestinationRootFolder'." -ForegroundColor Green
                    $FoldersMovedCount++
                }
                catch {
                    Write-Error "Failed to move '$FolderName'. Error: $_"
                }
            } else {
                Write-Host "Skipping folder: '$FolderName' (does not meet criteria)." -ForegroundColor DarkYellow
                $FoldersSkippedCount++
            }
        }
    }
    catch {
        Write-Error "An error occurred during folder processing: $_"
    }

    Write-Host "`n--- Script Summary ---"
    Write-Host "Folders moved: $FoldersMovedCount" -ForegroundColor Cyan
    Write-Host "Folders skipped: $FoldersSkippedCount" -ForegroundColor Yellow
    Write-Host "Operation complete." -ForegroundColor Green
}

# Call the function to run the script
Move-FoldersByPattern
