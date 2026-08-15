$GodotArgs = $args
$ErrorActionPreference = "Stop"
$projectAGodotExe = $env:PROJECT_A_GODOT_BIN
if ([string]::IsNullOrWhiteSpace($projectAGodotExe)) {
	$found = Get-Command godot, godot4 -ErrorAction SilentlyContinue | Select-Object -First 1
	if ($null -ne $found) { $projectAGodotExe = $found.Source }
}
if ([string]::IsNullOrWhiteSpace($projectAGodotExe) -or -not (Test-Path -LiteralPath $projectAGodotExe)) {
	throw "Set PROJECT_A_GODOT_BIN to the absolute Godot 4.7 executable path."
}

$projectPath = (Get-Location).Path
for ($index = 0; $index -lt $GodotArgs.Count - 1; $index++) {
	if ($GodotArgs[$index] -eq "--path") {
		$projectPath = $GodotArgs[$index + 1]
		break
	}
}
if (-not [System.IO.Path]::IsPathRooted($projectPath)) {
	$projectPath = Join-Path (Get-Location).Path $projectPath
}
$projectPath = [System.IO.Path]::GetFullPath($projectPath)
$projectFile = Join-Path $projectPath "project.godot"
$classCache = Join-Path $projectPath ".godot\global_script_class_cache.cfg"
$needsClassScan = -not (Test-Path -LiteralPath $classCache)
if (-not $needsClassScan) {
	$needsClassScan = (Get-Content -LiteralPath $classCache -Raw).Trim() -eq "list=[]"
}
if ((Test-Path -LiteralPath $projectFile) -and $needsClassScan -and $GodotArgs -notcontains "--editor") {
	& $projectAGodotExe --headless --path $projectPath --editor --quit
	if ($LASTEXITCODE -ne 0) {
		exit $LASTEXITCODE
	}
}
& $projectAGodotExe @GodotArgs
exit $LASTEXITCODE
