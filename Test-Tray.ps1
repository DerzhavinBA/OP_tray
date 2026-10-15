#Requires -Version 5.1
# OpenProject tray automated tests. UTF-8 with BOM recommended.
$ErrorActionPreference = 'Stop'

$TrayDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $TrayDir 'OpenProject-Tray.Core.ps1')
Initialize-OpenProjectTrayCore -TrayDir $TrayDir

$script:Pass = 0
$script:Fail = 0
$script:Results = @()

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        $script:Pass++
        $script:Results += "[PASS] $Name"
        Write-Host "[PASS] $Name" -ForegroundColor Green
    } else {
        $script:Fail++
        $msg = "[FAIL] $Name"
        if ($Detail) { $msg += " — $Detail" }
        $script:Results += $msg
        Write-Host $msg -ForegroundColor Red
    }
}

Write-Host "=== OpenProject Tray tests ===" -ForegroundColor Cyan
Write-Host "TrayDir=$TrayDir"
Write-Host "WslTrayDir=$($script:OpWslTrayDir)"
Write-Host "OpRoot=$($script:OpRoot)"

# 0) Settings defaults / validation (no WSL)
Write-Host "`n-- Settings --"
$defaults = Get-OpSettingsDefaults
Assert-True 'Default OpenProjectRoot' ($defaults.OpenProjectRoot -eq '/opt/openproject')
$merged = Merge-OpSettingsDefaults -Raw @{ Url = 'http://127.0.0.1:3001' }
Assert-True 'Merge keeps custom Url' ($merged.Url -eq 'http://127.0.0.1:3001')
Assert-True 'Merge fills Distro' ($merged.Distro -eq 'Debian')
$settingsThrew = $false
try {
    Assert-OpSettingsValid -Settings @{ OpenProjectRoot = 'relative/path' }
} catch {
    $settingsThrew = $true
}
Assert-True 'Reject relative OpenProjectRoot' $settingsThrew

$tmpSettings = Join-Path $TrayDir 'settings.json'
$hadSettings = Test-Path -LiteralPath $tmpSettings
$backup = $null
if ($hadSettings) { $backup = Get-Content -LiteralPath $tmpSettings -Raw -Encoding UTF8 }
try {
    $round = Write-OpSettings -TrayDir $TrayDir -Settings @{
        OpenProjectRoot      = '/opt/openproject'
        Distro               = 'Debian'
        LinuxUser            = 'openproject'
        Url                  = 'http://localhost:3000'
        StartWithWindows     = $false
        AutoStartOpenProject = $false
        OpenBrowserOnStart   = $true
        ColdReadyTimeoutSec  = 180
        WarmReadyTimeoutSec  = 90
        PrepareTimeoutSec    = 300
    }
    $readBack = Read-OpSettings -TrayDir $TrayDir
    Assert-True 'Read-OpSettings OpenProjectRoot' ($readBack.OpenProjectRoot -eq '/opt/openproject')
    Assert-True 'Write-OpSettings returns root' ($round.OpenProjectRoot -eq '/opt/openproject')
    Assert-True 'Default AutoStart is off' ($readBack.AutoStartOpenProject -eq $false)

    Write-OpActivityLog -Message 'тест журнала A'
    Write-OpActivityLog -Message 'тест журнала B'
    $logText = Read-OpActivityLogText -TrayDir $TrayDir
    Assert-True 'Activity log contains entries' ($logText -match 'тест журнала A' -and $logText -match 'тест журнала B')
    Assert-True 'Activity log has timestamps' ($logText -match '\d{2}\.\d{2}\.\d{4} \d{2}:\d{2}:\d{2}')
    Initialize-OpenProjectTrayCore -TrayDir $TrayDir
    Assert-True 'Init sets OpRoot' ($script:OpRoot -eq '/opt/openproject')
    Assert-True 'Init sets OpHttpPort' ($script:OpHttpPort -eq 3000)
    Assert-True 'Init AutoStartOpenProject false' (-not $script:OpAutoStartOpenProject)
} finally {
    if ($hadSettings -and $null -ne $backup) {
        [System.IO.File]::WriteAllText($tmpSettings, $backup, [System.Text.UTF8Encoding]::new($false))
    } elseif (-not $hadSettings -and (Test-Path -LiteralPath $tmpSettings)) {
        Remove-Item -LiteralPath $tmpSettings -Force
    }
    Initialize-OpenProjectTrayCore -TrayDir $TrayDir
}

Assert-True 'prepare script exists' (Test-Path (Join-Path $TrayDir 'op-tray-prepare.sh'))
Assert-True 'doctor script exists' (Test-Path (Join-Path $TrayDir 'op-tray-doctor.sh'))
Assert-True 'settings.example.json exists' (Test-Path (Join-Path $TrayDir 'settings.example.json'))
Assert-True 'Invoke-OpDoctorCheck exists' ($null -ne (Get-Command Invoke-OpDoctorCheck -ErrorAction SilentlyContinue))
Assert-True 'Get-OpPendingMigrationCount exists' ($null -ne (Get-Command Get-OpPendingMigrationCount -ErrorAction SilentlyContinue))
Assert-True 'Open-OpProjectTerminal exists' ($null -ne (Get-Command Open-OpProjectTerminal -ErrorAction SilentlyContinue))

# 1) Wake WSL after possible shutdown
Write-Host "`n-- Ensure-WslRunning (may wake distro) --"
try {
    Ensure-WslRunning
    Assert-True 'Ensure-WslRunning succeeds' $true
    Assert-True 'Distro listed as running' (Test-WslDistroRunning)
} catch {
    Assert-True 'Ensure-WslRunning succeeds' $false $_.Exception.Message
}

# 2) Bad distro name must throw (restore after)
Write-Host "`n-- Bad distro error path --"
$saved = $script:OpDistro
$script:OpDistro = 'NoSuchDistro_OpenProjectTray_Test'
$threw = $false
try {
    Ensure-WslRunning
} catch {
    $threw = $true
}
$script:OpDistro = $saved
Assert-True 'Ensure-WslRunning fails on bad distro' $threw

# 3) Postgres ready
Write-Host "`n-- Postgres --"
try {
    Start-PostgresReady
    Assert-True 'Start-PostgresReady' $true
} catch {
    Assert-True 'Start-PostgresReady' $false $_.Exception.Message
}

# 4) Stop then Start pipeline
Write-Host "`n-- Stop / Start / Fast / Duplicate --"
try {
    Stop-OpenProjectDevStack
    Start-Sleep -Seconds 3
    Assert-True 'Stop leaves :3000 down' (-not (Test-OpenProjectRunning))
} catch {
    Assert-True 'Stop-OpenProjectDevStack' $false $_.Exception.Message
}

try {
    $r1 = Start-OpenProjectPipeline
    Assert-True 'Start pipeline Ready' ([bool]$r1.Ready)
    Assert-True 'Start pipeline FullStart' ([bool]$r1.FullStart)
    Assert-True 'Start Mode Warm or Cold' ($r1.Mode -in @('Warm', 'Cold'))
    Assert-True 'HTTP up after Start' (Test-OpenProjectRunning)
} catch {
    Assert-True 'Start-OpenProjectPipeline' $false $_.Exception.Message
}

try {
    $before = Get-OpenProjectProcManagerCount
    $r2 = Start-OpenProjectPipeline
    $after = Get-OpenProjectProcManagerCount
    Assert-True 'Second Start is Fast path' ($r2.Mode -eq 'Fast' -and -not $r2.FullStart)
    Assert-True 'No duplicate proc managers' ($after -le $before -or $after -eq 1)
} catch {
    Assert-True 'Fast path / no duplicate' $false $_.Exception.Message
}

# 5) Restart (without migrate — migrate changes DB and is slower)
Write-Host "`n-- Restart --"
try {
    $rr = Restart-OpenProjectPipeline
    Assert-True 'Restart Ready' ([bool]$rr.Ready)
    Assert-True 'HTTP up after Restart' (Test-OpenProjectRunning)
    Assert-True 'Restart Mode' ($rr.Mode -eq 'Restart')
} catch {
    Assert-True 'Restart-OpenProjectPipeline' $false $_.Exception.Message
}

# 6) Browser helper exists (do not require interactive browser)
Assert-True 'Open-OpenProjectBrowser command exists' ($null -ne (Get-Command Open-OpenProjectBrowser -ErrorAction SilentlyContinue))
Assert-True 'Restart -WithMigrate command exists' ($null -ne (Get-Command Restart-OpenProjectPipeline -ErrorAction SilentlyContinue))

Write-Host "`n=== Summary: $($script:Pass) passed, $($script:Fail) failed ===" -ForegroundColor $(if ($script:Fail -eq 0) { 'Green' } else { 'Red' })
$script:Results | ForEach-Object { Write-Host $_ }

if ($script:Fail -gt 0) { exit 1 }
exit 0
