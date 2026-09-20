# Builds a Wago.io-ready zip of FieldJournal from the current working tree.
$ErrorActionPreference = "Stop"

Set-Location (Join-Path $PSScriptRoot "..")

$tocContent = Get-Content "FieldJournal.toc" -Raw
if ($tocContent -notmatch "## Version:\s*(\S+)") {
    throw "Could not find Version in FieldJournal.toc"
}
$version = $Matches[1]

$distDir = "dist"
$stageDir = Join-Path $distDir "FieldJournal"
$zipPath = Join-Path $distDir "FieldJournal-$version.zip"

if (Test-Path $distDir) { Remove-Item $distDir -Recurse -Force }
New-Item -ItemType Directory -Path $stageDir -Force | Out-Null

# Runtime files only: everything the .toc loads, plus assets it references
# and top-level docs. Excludes tests/, tools/, docs/, .claude/, .vscode/, .git/.
$runtimeDirs = @("Core", "Data", "UI", "Libs", "assets", "art")
foreach ($dir in $runtimeDirs) {
    Copy-Item -Path $dir -Destination (Join-Path $stageDir $dir) -Recurse
}
$runtimeFiles = @("FieldJournal.toc", "LICENSE", "README.md", "CHANGELOG.md")
foreach ($file in $runtimeFiles) {
    Copy-Item -Path $file -Destination $stageDir
}

Compress-Archive -Path $stageDir -DestinationPath $zipPath -Force

Remove-Item $stageDir -Recurse -Force

Write-Output "Packaged $zipPath"
