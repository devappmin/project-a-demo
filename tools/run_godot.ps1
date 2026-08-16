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

function Invoke-ProjectAGodotChecked {
	param([object[]]$InvocationArguments)

	$capturedOutput = @()
	& $projectAGodotExe @InvocationArguments 2>&1 | Tee-Object -Variable capturedOutput | Out-Host
	$engineExitCode = $LASTEXITCODE
	$outputText = ($capturedOutput | Out-String)
	$hasScriptFailure = $outputText -match "SCRIPT ERROR:" -or $outputText -match "ERROR:\s+(Failed to load script|Cannot load source code)"
	if ($engineExitCode -eq 0 -and $hasScriptFailure) {
		[Console]::Error.WriteLine("Godot reported a script-load failure despite returning exit code 0.")
		return 1
	}
	return $engineExitCode
}

$engineArgs = @()
foreach ($argument in $GodotArgs) {
	if ($argument -eq "--") {
		break
	}
	$engineArgs += $argument
}
$projectPath = (Get-Location).Path
for ($index = 0; $index -lt $engineArgs.Count - 1; $index++) {
	if ($engineArgs[$index] -eq "--path") {
		$projectPath = $engineArgs[$index + 1]
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
if ((Test-Path -LiteralPath $projectFile) -and $needsClassScan -and $engineArgs -notcontains "--editor") {
	$classScanExit = Invoke-ProjectAGodotChecked -InvocationArguments @("--headless", "--path", $projectPath, "--editor", "--quit")
	if ($classScanExit -ne 0) {
		exit $classScanExit
	}
}
$runExit = Invoke-ProjectAGodotChecked -InvocationArguments $GodotArgs
exit $runExit
