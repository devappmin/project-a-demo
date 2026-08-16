$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$fixtureRoot = Join-Path $repoRoot "tests\fixtures\fresh_project"
$scratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("project-a-clean-wrapper-" + [guid]::NewGuid().ToString("N"))

try {
	New-Item -ItemType Directory -Path $scratchRoot | Out-Null
	Copy-Item -LiteralPath (Join-Path $fixtureRoot "project.godot.fixture") -Destination (Join-Path $scratchRoot "project.godot")
	Copy-Item -LiteralPath (Join-Path $fixtureRoot "fresh_base.gd") -Destination $scratchRoot
	Copy-Item -LiteralPath (Join-Path $fixtureRoot "runner.gd") -Destination $scratchRoot

	$cachePath = Join-Path $scratchRoot ".godot\global_script_class_cache.cfg"
	if (Test-Path -LiteralPath $cachePath) {
		throw "Fresh fixture unexpectedly contains a Godot class cache."
	}

	Push-Location $scratchRoot
	try {
		& pwsh -NoProfile -File (Join-Path $repoRoot "tools\run_godot.ps1") --headless --script res://runner.gd -- --editor --path not-an-engine-project
	}
	finally {
		Pop-Location
	}
	if ($LASTEXITCODE -ne 0) {
		throw "Script arguments after -- must not suppress or redirect the wrapper's fresh-project class bootstrap."
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
		(Split-Path -Leaf $resolvedScratch).StartsWith("project-a-clean-wrapper-") -and
		(Test-Path -LiteralPath $resolvedScratch)) {
		[System.IO.Directory]::Delete($resolvedScratch, $true)
	}
}
