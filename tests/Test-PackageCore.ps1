#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'OpenProject-Tray.Core.ps1')
Initialize-OpenProjectTrayCore -TrayDir $root
function Assert($condition, $message) { if (-not $condition) { throw $message } }
$script:commands = @()
$script:fakeStatus = 'RUNNING'
$script:fakeExit = 0
function Ensure-WslRunning { }
function Test-WslDistroRunning { $true }
function Invoke-WslProcess {
    param($ArgumentList, $TimeoutSec)
    $script:commands += ,@($ArgumentList)
    $command = $ArgumentList[-1]
    if ($command -match 'status') { return @{ExitCode=0; StdOut=$script:fakeStatus; StdErr=''} }
    if ($command -match 'pending') { return @{ExitCode=$script:fakeExit; StdOut='2'; StdErr=''} }
    return @{ExitCode=$script:fakeExit; StdOut=''; StdErr='simulated failure'}
}
function Test-OpHttpReady { $script:httpReady }
$script:httpReady = $true
Assert ((Get-OpSettingsDefaults).Url -eq 'http://127.0.0.1') 'Packaged default URL must use proxy'
$health = Get-OpPackageHealth
Assert ($health.State -eq 'Running') 'Healthy services + HTTP must be Running'
$script:fakeStatus = 'ERROR web=active worker=failed'
$health = Get-OpPackageHealth
Assert ($health.State -eq 'Error') 'Dead worker with healthy HTTP must be Error'
$script:fakeStatus = 'STOPPED'
Assert ((Get-OpPackageHealth).State -eq 'Stopped') 'Stopped services must stay Stopped behind proxy'
$script:fakeStatus = 'RUNNING'
$script:httpReady = $false
Assert ((Get-OpPackageHealth).State -eq 'Error') 'HTTP failure must not show Running'
$script:httpReady = $true
$script:commands = @()
Stop-OpenProjectService
Assert (($script:commands[-1] -join ' ') -match '-u root.*stop') 'Stop must use privileged service command'
Assert ((Get-OpPendingMigrationCount).Pending -eq 2) 'Parse package migration count'
$script:fakeExit = 1
$failed = $false
try { Get-OpPendingMigrationCount | Out-Null } catch { $failed = $true }
Assert $failed 'Nonzero CLI result must never become a migration count'
$script:distRunning = $false
$script:readyTimeout = 0
function Test-WslDistroRunning { $script:distRunning }
function Ensure-WslRunning { $script:distRunning = $true }
function Test-OpenProjectRunning { $false }
function Start-OpenProjectService { }
function Wait-OpenProjectReady { param($TimeoutSec) $script:readyTimeout = $TimeoutSec; $true }
$r = Start-OpenProjectPipeline
Assert ($r.Mode -eq 'Cold' -and $script:readyTimeout -eq 180) 'Capture cold state before waking distro'
function Test-WslDistroRunning { $true }
function Ensure-WslRunning { }
$script:order = @()
function Stop-OpenProjectService { $script:order += 'stop' }
function Invoke-OpenProjectPrepare { $script:order += 'migrate'; throw 'migration failed' }
function Start-OpenProjectService { $script:order += 'start' }
$failed = $false
try { Restart-OpenProjectPipeline -WithMigrate | Out-Null } catch { $failed = $true }
Assert ($failed -and ($script:order -join ',') -eq 'stop,migrate') 'Failed migration must leave services stopped'
function Invoke-OpenProjectPrepare { $script:order += 'migrate' }
function Wait-OpenProjectReady { $true }
$script:order = @()
$null = Restart-OpenProjectPipeline -WithMigrate
Assert (($script:order -join ',') -eq 'stop,migrate,start') 'Successful migration must restart in order'
function Wait-OpenProjectReady { $false }
$failed = $false
try { Restart-OpenProjectPipeline | Out-Null } catch { $failed = $true }
Assert $failed 'Readiness timeout must fail the operation'
function Test-WslDistroRunning { throw 'WSL unavailable' }
Assert ((Get-OpPackageHealth).State -eq 'Error') 'WSL failure must be reported'
function Test-WslDistroRunning { $false }
Assert ((Get-OpPackageHealth).State -eq 'Stopped') 'Monitoring must not wake a stopped distro'
# Settings changes require positive package identification and preserve the original.
$fixture = Join-Path $root ('build/obj/package-settings-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$settings = Get-OpSettingsDefaults
$settings.Url = 'http://localhost:3000'
$null = Write-OpSettings $fixture $settings
Initialize-OpenProjectTrayCore -TrayDir $fixture
$script:fakeExit = 1
$failed = $false
try { Update-OpPackagedSettings | Out-Null } catch { $failed = $true }
Assert ($failed -and (Read-OpSettings $fixture).Url -eq 'http://localhost:3000') 'Missing package must preserve URL'
$script:fakeExit = 0
Assert (Update-OpPackagedSettings) 'Confirmed package must migrate old default URL'
Assert ((Read-OpSettings $fixture).Url -eq 'http://127.0.0.1') 'Save migrated URL'
$backups = @(Get-ChildItem $fixture -Filter '*.bak')
Assert ($backups.Count -eq 1 -and (Get-Content $backups[0].FullName -Raw | ConvertFrom-Json).Url -eq 'http://localhost:3000') 'Backup must preserve old settings'
$settings.Url = 'http://localhost'
$null = Write-OpSettings $fixture $settings
Initialize-OpenProjectTrayCore -TrayDir $fixture
Assert (Update-OpPackagedSettings) 'Migrate previous packaged localhost default'
Assert ((Read-OpSettings $fixture).Url -eq 'http://127.0.0.1') 'Previous package default must use IPv4'
$settings.Url = 'https://example.test/openproject'
Initialize-OpenProjectTrayCore -TrayDir $fixture -Settings $settings
Assert (-not (Update-OpPackagedSettings)) 'Custom URL must be preserved'
Assert ($script:OpLoginUrl -eq 'https://example.test/openproject/login') 'Keep HTTPS and subpath in health URL'
$settings.Url = 'https://localhost'
Initialize-OpenProjectTrayCore -TrayDir $fixture -Settings $settings
Assert ($script:OpLoginUrl -eq 'https://localhost/login') 'Preserve certificate hostname for HTTPS localhost'
$settings.Url = 'http://localhost'
Initialize-OpenProjectTrayCore -TrayDir $fixture -Settings $settings
Assert ($script:OpLoginUrl -eq 'http://127.0.0.1/login') 'HTTP localhost uses IPv4 for WSL forwarding on Windows'
Write-Host 'PASS packaged core: services, HTTP, command privileges, migration ordering and failure'
