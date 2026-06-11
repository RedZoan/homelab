# PowerShell Command to Create a Text File of Folder Paths for rsync

# --- Instructions ---
# 1. Run this script in a PowerShell terminal.
# 2. You will be prompted to enter the source directory and the output file path.

# --- User Input ---

# Prompt the user for the source directory to scan.
$sourceDirectory = Read-Host -Prompt "Enter the source directory (e.g., C:\Users\YourUser\Documents)"

# Prompt the user for the path to save the output file.
$outputFile = Read-Host -Prompt "Enter the path for the output file (e.g., C:\temp\folder-list.txt)"

# --- Script ---

# Get all directories within the source directory, including subdirectories.
# -Directory: Specifies that we only want to list directories.
# -Recurse: Goes through all subdirectories.
# -Path: The starting directory for the search.
# Select-Object -ExpandProperty FullName: Extracts the full path for each directory.
# Out-File: Writes the output to the specified text file.
try {
    Write-Host "Searching for directories in '$sourceDirectory'..."
    
    Get-ChildItem -Path $sourceDirectory -Directory -Recurse | Select-Object -ExpandProperty FullName | Out-File -FilePath $outputFile -Encoding utf8
    
    Write-Host "Success! Directory list saved to '$outputFile'"
}
catch {
    Write-Host "An error occurred:"
    Write-Host $_.Exception.Message
}

