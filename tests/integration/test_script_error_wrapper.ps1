$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$fixtureRoot = Join-Path $repoRoot "tests\fixtures\broken_script_project"
$scratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("project-a-broken-wrapper-" + [guid]::NewGuid().ToString("N"))

try {
	New-Item -ItemType Directory -Path $scratchRoot | Out-Null
	Copy-Item -LiteralPath (Join-Path $fixtureRoot "project.godot.fixture") -Destination (Join-Path $scratchRoot "project.godot")
	Copy-Item -LiteralPath (Join-Path $fixtureRoot "broken_runner.gd.fixture") -Destination (Join-Path $scratchRoot "broken_runner.gd")
	Copy-Item -LiteralPath (Join-Path $fixtureRoot "broken_dependency.gd.fixture") -Destination (Join-Path $scratchRoot "broken_dependency.gd")

	Push-Location $scratchRoot
	try {
		$output = & pwsh -NoProfile -File (Join-Path $repoRoot "tools\run_godot.ps1") --headless --path . --script res://broken_runner.gd 2>&1 | Out-String
		$wrapperExit = $LASTEXITCODE
	}
	finally {
		Pop-Location
	}

	if ($output -notmatch "SCRIPT ERROR:|Failed to load script") {
		throw "The deliberately broken fixture did not reproduce a Godot script-load error."
	}
	if ($wrapperExit -eq 0) {
		throw "The supported wrapper returned zero after a Godot script-load error."
	}
}
finally {
	$resolvedScratch = [System.IO.Path]::GetFullPath($scratchRoot)
	$resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
	if ($resolvedScratch.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase) -and
		(Split-Path -Leaf $resolvedScratch).StartsWith("project-a-broken-wrapper-") -and
		(Test-Path -LiteralPath $resolvedScratch)) {
		[System.IO.Directory]::Delete($resolvedScratch, $true)
	}
}
