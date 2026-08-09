param([Parameter(ValueFromRemainingArguments = $true)][string[]]$GodotArgs)
$ErrorActionPreference = "Stop"
$projectAGodotExe = $env:PROJECT_A_GODOT_BIN
if ([string]::IsNullOrWhiteSpace($projectAGodotExe)) {
	$found = Get-Command godot, godot4 -ErrorAction SilentlyContinue | Select-Object -First 1
	if ($null -ne $found) { $projectAGodotExe = $found.Source }
}
if ([string]::IsNullOrWhiteSpace($projectAGodotExe) -or -not (Test-Path -LiteralPath $projectAGodotExe)) {
	throw "Set PROJECT_A_GODOT_BIN to the absolute Godot 4.7 executable path."
}
& $projectAGodotExe @GodotArgs
exit $LASTEXITCODE
