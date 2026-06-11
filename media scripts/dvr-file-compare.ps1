<#
.SYNOPSIS
    Compares media files between two directories and reports files that exist in both.

.DESCRIPTION
    Scans a source and destination directory for media files (.ts, .mp4, .mkv), then identifies
    files in the source that have a matching counterpart in the destination based on a "cleaned"
    filename comparison. Cleaning strips episode codes (S01E01), bracketed tags, years in
    parentheses, and common network suffixes so that logically identical files are matched even
    if their names differ slightly.

    Results are displayed on screen and exported to a CSV file of your choosing.

    Use dvr-file-unique.ps1 to find the inverse — files in the source that have NO match.

.PARAMETER SourceDirectory
    The root folder to scan for source media files. Searched recursively.

.PARAMETER DestinationDirectory
    The root folder to compare against. Searched recursively.

.PARAMETER OutputFile
    The full path for the output CSV file (e.g., C:\Reports\MatchedFiles.csv).

.EXAMPLE
    # Run the script and follow the prompts.
    .\dvr-file-compare.ps1
#>

# Prompt the user for source, destination, and output directories
$SourceDirectory = Read-Host "Enter the FULL path to the SOURCE directory (e.g., C:\MyFiles\Source)"
$DestinationDirectory = Read-Host "Enter the FULL path to the DESTINATION directory (e.g., C:\MyFiles\Destination)"
$OutputFile = Read-Host "Enter the FULL path for the OUTPUT CSV file (e.g., C:\Reports\MatchedFiles.csv)"

# Define the allowed file extensions for comparison
$AllowedExtensions = @(".ts", ".mp4", ".mkv")

# Function to clean the filename by removing season and episode patterns,
# bracketed information, years in parentheses, and common network suffixes.
function Clean-FileName {
    param (
        [string]$FileName
    )
    # Get the base name (filename without extension)
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $cleaned = $baseName

    # 1. Remove season and episode patterns (e.g., " - SXXEXX" or " - SXXEXXX")
    # This regex looks for patterns like " - S" followed by two digits for season,
    # "E" followed by two or three digits for episode.
    $cleaned = $cleaned -replace ' - S\d{2}E\d{2,3}', ''

    # 2. Remove anything in between square brackets, including the brackets themselves,
    # and any leading whitespace before the brackets.
    # The '?' makes the match non-greedy, so it stops at the first closing bracket.
    $cleaned = $cleaned -replace '\s*\[.*?\]', ''

    # 3. Remove year in parentheses (e.g., " (2016)").
    # This regex looks for a space followed by a literal opening parenthesis,
    # four digits, and a literal closing parenthesis.
    $cleaned = $cleaned -replace '\s*\(\d{4}\)', ''

    # 4. Remove common network suffixes (e.g., " NBC").
    # This regex specifically targets " NBC" at a word boundary to prevent
    # removing "NBC" if it's part of a legitimate show title (e.g., "NBC Nightly News").
    # Given the user's example, it implies " NBC" should be normalized.
    $cleaned = $cleaned -replace ' NBC\b', ''

    # Trim any leading/trailing whitespace that might result from cleaning
    $cleaned = $cleaned.Trim()

    return $cleaned
}

Write-Host "Scanning source directory: $SourceDirectory..."
# Get all files from the source directory, recursively, and filter by allowed extensions
$SourceFiles = Get-ChildItem -Path "$SourceDirectory" -Recurse -File |
    Where-Object { $AllowedExtensions -contains $_.Extension.ToLower() } |
    Select-Object FullName, Name, Extension

Write-Host "Scanning destination directory: $DestinationDirectory..."
# Get all files from the destination directory, recursively, and filter by allowed extensions
# FIX: Enclose $DestinationDirectory in double quotes
$DestinationFiles = Get-ChildItem -Path "$DestinationDirectory" -Recurse -File |
    Where-Object { $AllowedExtensions -contains $_.Extension.ToLower() } |
    Select-Object FullName, Name, Extension

# Create a hash table for quick lookups of destination files
# The key will be the cleaned filename (without extension), and the value will be the full path
$DestinationFileLookup = @{}
foreach ($file in $DestinationFiles) {
    $cleanedName = Clean-FileName -FileName $file.Name
    # Using the cleaned name as the key. If duplicates exist, the last one wins, but for lookup it's fine.
    $DestinationFileLookup[$cleanedName] = $file.FullName
}

Write-Host "Comparing files..."
# List to store the matched files
$MatchedFiles = @()

# Iterate through source files and compare with destination files
foreach ($sourceFile in $SourceFiles) {
    # Clean the source filename (without its extension) for comparison
    $cleanedSourceName = Clean-FileName -FileName $sourceFile.Name

    # Check if the cleaned source filename exists in our destination lookup table
    if ($DestinationFileLookup.ContainsKey($cleanedSourceName)) {
        # If a match is found, add the source file's information to our list
        $MatchedFiles += [PSCustomObject]@{
            SourceFilePath = $sourceFile.FullName
            SourceFileName = $sourceFile.Name
            SourceFileExtension = $sourceFile.Extension # Include source extension
            CleanedFileName = $cleanedSourceName
            # The DestinationFilePath from the lookup will have the destination's actual extension
            DestinationFilePath = $DestinationFileLookup[$cleanedSourceName]
            DestinationFileExtension = ([System.IO.Path]::GetExtension($DestinationFileLookup[$cleanedSourceName])).ToLower() # Get destination extension
        }
    }
}

# Display the matched files on the screen
if ($MatchedFiles.Count -gt 0) {
    Write-Host "`n--- Matched Files ---"
    # Display relevant columns for clarity
    $MatchedFiles | Format-Table -Property SourceFileName, SourceFileExtension, DestinationFileExtension, CleanedFileName -AutoSize
    Write-Host "---------------------`n"

    # Export the matched files to a CSV
    $MatchedFiles | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8
    Write-Host "Comparison complete. Found $($MatchedFiles.Count) matching files."
    Write-Host "Results exported to: $OutputFile"
} else {
    Write-Host "No matching files found based on the comparison criteria."
}
