param(
  [string]$Destination = "C:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns\TickPulse"
)

$ErrorActionPreference = "Stop"

$sourceRoot = $PSScriptRoot
$scriptName = Split-Path -Leaf $MyInvocation.MyCommand.Path

if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot "TickPulse.toc"))) {
  throw "TickPulse.toc was not found in $sourceRoot. Run this script from inside the addon repository."
}

try {
  New-Item -ItemType Directory -Path $Destination -Force | Out-Null
}
catch {
  throw "Unable to create or access destination '$Destination'. Try running PowerShell as Administrator."
}

$files = Get-ChildItem -LiteralPath $sourceRoot -Recurse -File | Where-Object {
  $_.FullName -notmatch "\\.git(\\|$)" -and $_.Name -ne $scriptName
}

$copied = 0
foreach ($file in $files) {
  $relativePath = $file.FullName.Substring($sourceRoot.Length).TrimStart('\\')
  $targetPath = Join-Path $Destination $relativePath
  $targetDir = Split-Path -Path $targetPath -Parent

  if (-not (Test-Path -LiteralPath $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
  }

  Copy-Item -LiteralPath $file.FullName -Destination $targetPath -Force
  $copied++
}

Write-Host "TickPulse updated successfully. Copied $copied file(s) to:"
Write-Host "  $Destination"