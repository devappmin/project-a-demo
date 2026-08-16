$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path

Push-Location $repoRoot
try {
	$output = & pwsh -NoProfile -File (Join-Path $repoRoot "tools\run_godot.ps1") --headless --path . --editor --quit 2>&1 | Out-String
	$wrapperExit = $LASTEXITCODE
}
finally {
	Pop-Location
}

if ($wrapperExit -ne 0) {
	throw "The outer project editor scan returned exit $wrapperExit.`n$output"
}
if ($output -match "Detected another project\.godot") {
	throw "The outer project editor scan discovered the intentionally broken nested fixture.`n$output"
}
if ($output -match "SCRIPT ERROR:|Failed to load script|Cannot load source code") {
	throw "The outer project editor scan reported a script-load failure.`n$output"
}
