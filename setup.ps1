# Vibe-To-Do setup for Windows — installs Bun if needed, then starts the server.
#
#   powershell -ExecutionPolicy Bypass -File setup.ps1              install deps + run the server
#   powershell -ExecutionPolicy Bypass -File setup.ps1 -AutoStart   also start it at every logon
param(
    [switch]$AutoStart
)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$Port = if ($env:PORT) { $env:PORT } else { 7788 }

# -- 1. Bun (the only dependency) ----------------------------------------
if (-not (Get-Command bun -ErrorAction SilentlyContinue)) {
    Write-Host '-> Bun not found - installing (https://bun.sh)...'
    Invoke-RestMethod 'https://bun.sh/install.ps1' | Invoke-Expression
    $env:Path = "$env:USERPROFILE\.bun\bin;$env:Path"
}
if (-not (Get-Command bun -ErrorAction SilentlyContinue)) {
    Write-Host "x Bun installed but 'bun' is not on PATH. Open a new terminal and re-run setup.ps1"
    exit 1
}
$Bun = (Get-Command bun).Source
Write-Host "-> Bun $(bun --version) at $Bun"

# -- 2. Optional: start at logon (Task Scheduler) -------------------------
if ($AutoStart) {
    $action   = New-ScheduledTaskAction -Execute $Bun -Argument 'server.ts' -WorkingDirectory $PSScriptRoot
    $trigger  = New-ScheduledTaskTrigger -AtLogOn
    $settings = New-ScheduledTaskSettingsSet -Hidden -ExecutionTimeLimit ([TimeSpan]::Zero) `
                  -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
    Register-ScheduledTask -TaskName 'Vibe-To-Do' -Action $action -Trigger $trigger `
        -Settings $settings -Description 'Vibe-To-Do local task server' -Force | Out-Null
    Start-ScheduledTask -TaskName 'Vibe-To-Do'
    Start-Sleep -Seconds 2
    try {
        Invoke-RestMethod "http://localhost:$Port/api/health" | Out-Null
        Write-Host "OK Vibe-To-Do is running -> http://localhost:$Port (and will start at every logon)"
    } catch {
        Write-Host '... task registered; if the server is not up yet, check server.log'
    }
    exit 0
}

# -- 3. Foreground run -----------------------------------------------------
Write-Host "-> Starting Vibe-To-Do on http://localhost:$Port  (Ctrl+C to stop)"
& $Bun server.ts
