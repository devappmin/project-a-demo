$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$fixtureRoot = Join-Path $repoRoot "tests\fixtures\fresh_project"
$scratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("project-a-clean-wrapper-" + [guid]::NewGuid().ToString("N"))

New-Item -ItemType Directory -Path $scratchRoot | Out-Null
Copy-Item -LiteralPath (Join-Path $fixtureRoot "project.godot") -Destination $scratchRoot
Copy-Item -LiteralPath (Join-Path $fixtureRoot "fresh_base.gd") -Destination $scratchRoot
Copy-Item -LiteralPath (Join-Path $fixtureRoot "runner.gd") -Destination $scratchRoot

try {
	$cachePath = Join-Path $scratchRoot ".godot\global_script_class_cache.cfg"
	if (Test-Path -LiteralPath $cachePath) {
		throw "Fresh fixture unexpectedly contains a Godot class cache."
	}

	& pwsh -NoProfile -File (Join-Path $repoRoot "tools\run_godot.ps1") --headless --path $scratchRoot --script res://runner.gd
	if ($LASTEXITCODE -ne 0) {
		throw "The project-local wrapper must bootstrap a fresh project's global script classes before running scripts."
	}

	if (-not (Test-Path -LiteralPath $cachePath)) {
		throw "The wrapper did not create the fresh project's global script class cache."
	}
	$cache = Get-Content -LiteralPath $cachePath -Raw
	if ($cache -notmatch '"class": &"FreshBase"') {
		throw "The fresh project's class cache does not contain FreshBase."
	}
}
finally {
	$resolvedScratch = [System.IO.Path]::GetFullPath($scratchRoot)
	$resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
	if ($resolvedScratch.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase) -and
		(Split-Path -Leaf $resolvedScratch).StartsWith("project-a-clean-wrapper-")) {
		[System.IO.Directory]::Delete($resolvedScratch, $true)
	}
}
