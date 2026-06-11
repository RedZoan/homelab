<#
.SYNOPSIS
    Maps a directory structure to a CSV file using Robocopy, bypassing the 260-character Windows path limit.

.DESCRIPTION
    Prompts for a root directory and an optional depth limit, then uses Robocopy in list-only
    mode (/L) to enumerate all subdirectories. Because Robocopy operates outside PowerShell's
    path handling, it correctly processes paths longer than 260 characters : a common problem
    with large music libraries where nested Artist/Album/Track folder names can be lengthy.

    Output is identical in structure to Directory-Crawler.ps1 (in media scripts): each row
    represents one subdirectory and includes its Depth, FullName, and individual Level_1,
    Level_2, ... columns for easy filtering in Excel.

    Results are saved to DirectoryStructure.csv on your Desktop.

.PARAMETER TargetPath
    Prompted interactively. The root directory to scan.

.PARAMETER DepthInput
    Prompted interactively. How many levels deep to search. Press Enter to scan all levels.

.EXAMPLE
    # Run the script and follow the prompts
    .\Directory-Crawler-Robocopy.ps1

.NOTES
    - Use this script instead of Directory-Crawler.ps1 when paths may exceed 260 characters.
    - Requires Robocopy (included with Windows).
    - Output is always saved to: [Desktop]\DirectoryStructure.csv
    - Robocopy counts the root as depth level 1 internally; the script adjusts for this so
      that the depth you enter matches what PowerShell's Get-ChildItem -Depth would produce.
#>

# 1. Prompt for Source Directory
$TargetPath = Read-Host -Prompt "Enter the full path of the Source Directory"

# Test-Path may fail on paths exceeding 260 characters, so treat it as a warning rather than a hard stop
if (-not (Test-Path -LiteralPath $TargetPath)) {
    Write-Warning "Note: PowerShell cannot verify this path (it may exceed 260 characters), but Robocopy will attempt to scan it anyway."
}

# 2. Prompt for Depth
$DepthInput = Read-Host -Prompt "Enter subdirectory depth (Press [Enter] for unlimited)"
$OutputPath = "$([Environment]::GetFolderPath('Desktop'))\DirectoryStructure.csv"

Write-Host "Scanning with Robocopy (handles long paths)..." -ForegroundColor Cyan

# 3. Construct Robocopy Arguments
# /L   = List only : no files are copied or moved
# /E   = Recursive, including empty subdirectories
# /NFL = No File List : suppress individual file names, only show folders
# /NJH = No Job Header
# /NJS = No Job Summary
# /FP  = Full Path : output the complete path for each folder
# /NC  = No Class : suppress the "New Dir" / "Existing Dir" labels
# /NS  = No Size : suppress file size output
$roboArgs = @($TargetPath, "NULL", "/L", "/E", "/NFL", "/NJH", "/NJS", "/FP", "/NC", "/NS")

# Robocopy's /LEV counts the root as level 1, so add 1 to match the user's expected depth
if (-not [string]::IsNullOrWhiteSpace($DepthInput)) {
    $roboLevel = [int]$DepthInput + 1
    $roboArgs += "/LEV:$roboLevel"
}

# 4. Run Robocopy in list-only mode and capture the folder output
$folderList = & robocopy $roboArgs

# 5. Parse and structure the results
$results = @()

foreach ($line in $folderList) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }

    $fullPath = $line.Trim()

    # Filter out any stray header/error lines by confirming the line starts with the target path
    if (-not $fullPath.StartsWith($TargetPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        continue
    }

    # Strip the root path to get the relative portion (e.g., "\Artist\Album")
    $relativePath = $fullPath.Substring($TargetPath.Length)
    if ($relativePath.StartsWith("\")) {
        $relativePath = $relativePath.Substring(1)
    }

    # Split relative path into individual folder-name segments
    $pathSegments = $relativePath -split "\\"

    # Skip the root folder entry itself (empty relative path)
    if ($pathSegments.Count -eq 0 -or ($pathSegments.Count -eq 1 -and $pathSegments[0] -eq "")) { continue }

    $objProperties = [ordered]@{
        "Depth"    = $pathSegments.Count
        "FullName" = $fullPath
    }

    # Dynamically add Level_1, Level_2, ... columns for each path segment
    for ($i = 0; $i -lt $pathSegments.Count; $i++) {
        $objProperties["Level_$($i + 1)"] = $pathSegments[$i]
    }

    $results += New-Object PSCustomObject -Property $objProperties
}

# 6. Export to CSV
if ($results.Count -gt 0) {
    $results | Export-Csv -Path $OutputPath -NoTypeInformation
    Write-Host "Success! Scanned $($results.Count) folders." -ForegroundColor Green
    Write-Host "File saved to: $OutputPath" -ForegroundColor Green
} else {
    Write-Warning "No folders found. Check your path and permissions."
}
