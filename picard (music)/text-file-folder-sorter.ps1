<#
.SYNOPSIS
    Splits a master folder list into alphabetical batch text files containing only top-level directories.

.DESCRIPTION
    Reads a master list of folder paths (e.g., the output of rsync-folder-text-file.ps1 or a
    Directory-Crawler export) and filters it down to only the top-level directories directly under
    a specified source root. It then categorises those paths by the first character of the folder
    name and writes one text file per letter (A.txt, B.txt, ...), plus _Numbers.txt and _Special.txt
    for paths starting with a digit or symbol.

    The resulting batch files are designed to be fed into robocopy-from-list-v3.ps1, which copies
    each batch to a destination using Robocopy. This two-step approach lets you copy a large music
    library in manageable alphabetical chunks.

.PARAMETER inputFileList
    Prompted interactively. Path to the master text file containing folder paths, one per line.

.PARAMETER sourceRootDirectory
    Prompted interactively. The root of your music library. Only paths whose immediate parent
    matches this root are included (i.e., Artist-level folders, not Album subfolders).

.PARAMETER outputDirectory
    Prompted interactively. Where the alphabetical .txt batch files will be written.
    Created automatically if it does not exist.

.EXAMPLE
    # Run the script and follow the prompts
    .\text-file-folder-sorter.ps1

.NOTES
    - Pairs with robocopy-from-list-v3.ps1 for batch Robocopy operations.
    - Duplicate paths in the master list are deduplicated via Get-Unique before categorising.
    - Paths are sorted alphabetically within each output file.
    - Path comparison is case-insensitive (PowerShell's default -eq behaviour).
#>

# --- User Input ---

$inputFileList       = Read-Host -Prompt "Enter the path to the master text file list (e.g., C:\temp\music-library.txt)"
$sourceRootDirectory = Read-Host -Prompt "Enter the source root of your music library (e.g., \\nas\music)"
$outputDirectory     = Read-Host -Prompt "Enter the destination directory for the new text files (e.g., D:\BatchLists)"

# --- Script ---

# Validate paths
if (-not (Test-Path -Path $inputFileList)) {
    Write-Host "Error: The file list '$inputFileList' was not found." -ForegroundColor Red
    Read-Host -Prompt "Press Enter to exit"
    exit
}
if (-not (Test-Path -Path $outputDirectory)) {
    Write-Host "Creating output directory: $outputDirectory"
    New-Item -Path $outputDirectory -ItemType Directory -Force | Out-Null
}

# Create a hashtable to store the categorized paths
$categorizedPaths = @{}

# Read the input file and filter for ONLY top-level directories, then get unique entries.
# A path is top-level if its immediate parent equals the source root (i.e., it's an Artist folder,
# not an Album or Track subfolder deeper in the tree).
Write-Host "Reading and parsing for top-level folders..."
$topLevelFolders = Get-Content -Path $inputFileList | Where-Object {
    (Split-Path -Path $_ -Parent) -eq $sourceRootDirectory
} | Get-Unique

Write-Host "Found $($topLevelFolders.Count) unique top-level artist folders to categorize." -ForegroundColor Green

# Categorize each top-level folder path by the first character of its folder name
foreach ($path in $topLevelFolders) {
    try {
        $artistName = Split-Path -Path $path -Leaf
        if ([string]::IsNullOrEmpty($artistName)) { continue }

        $firstChar = $artistName[0]

        # Assign a category key that will become the output filename (A, B, ..., _Numbers, _Special)
        $categoryKey = switch ($firstChar) {
            { [char]::IsLetter($_) } { $_.ToString().ToUpper(); break }
            { [char]::IsDigit($_) }  { "_Numbers"; break }
            default                  { "_Special" }
        }

        # Add to the appropriate category list, creating it if this is the first entry
        if (-not $categorizedPaths.ContainsKey($categoryKey)) {
            $categorizedPaths[$categoryKey] = [System.Collections.Generic.List[string]]::new()
        }
        $categorizedPaths[$categoryKey].Add($path)
    }
    catch {
        Write-Host "An error occurred while processing '$path':" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
    }
}

# Write each category to its own alphabetically-sorted text file
Write-Host "Writing categorized files to '$outputDirectory'..."
foreach ($category in $categorizedPaths.Keys | Sort-Object) {
    $outputFilePath = Join-Path -Path $outputDirectory -ChildPath "$($category).txt"
    try {
        $sortedPaths = $categorizedPaths[$category] | Sort-Object
        Set-Content -Path $outputFilePath -Value $sortedPaths
        Write-Host "Created '$outputFilePath' with $($sortedPaths.Count) entries." -ForegroundColor Cyan
    }
    catch {
        Write-Host "An error occurred writing to '$outputFilePath':" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
    }
}

Write-Host "Process completed. Your batch files are ready." -ForegroundColor Green
