<#
.SYNOPSIS
    Maps a directory structure to a CSV file, with optional depth limiting.

.DESCRIPTION
    Prompts for a root directory and an optional search depth, then recursively scans
    for all subdirectories. Results are exported to a CSV on your Desktop named
    'DirectoryStructure.csv'.

    Each row in the CSV represents one directory and includes:
      - Depth: how many levels deep it sits below the root
      - FullName: the complete path
      - Level_1, Level_2, ...: the individual folder name at each depth level

    This makes it easy to sort, filter, and analyze a large folder hierarchy in Excel
    or any spreadsheet application.

.PARAMETER TargetPath
    Prompted interactively. The root directory to scan (e.g., C:\Media).

.PARAMETER DepthInput
    Prompted interactively. How many levels deep to search. Press Enter to scan all levels.

.EXAMPLE
    # Run the script and follow the prompts.
    .\Directory-Crawler.ps1

.NOTES
    Output is always saved to: [Desktop]\DirectoryStructure.csv
#>

# 1. Prompt the user for the Source Directory
$TargetPath = Read-Host -Prompt "Enter the full path of the Source Directory (e.g. C:\Media)"

# Validate the path
if (-not (Test-Path $TargetPath)) {
    Write-Warning "The path '$TargetPath' does not exist. Script aborted."
    exit
}

# 2. Prompt for Depth (Optional)
$DepthInput = Read-Host -Prompt "Enter how many levels deep to search (Press [Enter] for unlimited)"
$OutputPath = "$([Environment]::GetFolderPath('Desktop'))\DirectoryStructure.csv"

Write-Host "Scanning..." -ForegroundColor Cyan

# 3. Retrieve Directories based on depth preference
try {
    if ([string]::IsNullOrWhiteSpace($DepthInput)) {
        # If user hit Enter, scan everything
        $directories = Get-ChildItem -Path $TargetPath -Directory -Recurse -ErrorAction Stop
    }
    else {
        # If user entered a number, limit the depth
        $directories = Get-ChildItem -Path $TargetPath -Directory -Depth $DepthInput -ErrorAction Stop
    }
}
catch {
    Write-Error "Error accessing directories. Please check permissions."
    exit
}

# Initialize results array
$results = @()

foreach ($dir in $directories) {
    # Calculate relative path to ignore the root folder part
    $relativePath = $dir.FullName.Substring($TargetPath.Length)
    
    # Clean up leading slashes
    if ($relativePath.StartsWith("\")) {
        $relativePath = $relativePath.Substring(1)
    }

    # Split into segments
    $pathSegments = $relativePath -split "\\"

    # Create ordered object
    $objProperties = [ordered]@{
        "Depth"    = $pathSegments.Count
        "FullName" = $dir.FullName
    }

    # Dynamically create Level_1, Level_2, etc.
    for ($i = 0; $i -lt $pathSegments.Count; $i++) {
        $columnName = "Level_$($i + 1)"
        $objProperties[$columnName] = $pathSegments[$i]
    }

    $results += New-Object PSCustomObject -Property $objProperties
}

# Export to CSV on the Desktop
$results | Export-Csv -Path $OutputPath -NoTypeInformation

Write-Host "Success! File saved to: $OutputPath" -ForegroundColor Green