#Requires -Version 5.1
# Runs the real UI and launcher against a private pipe and a fake core. Never calls WSL.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$id = [Guid]::NewGuid().ToString('N')
$sandbox = Join-Path $root "build/obj/integration-$id"
[void][IO.Directory]::CreateDirectory($sandbox)
Copy-Item -Path (Join-Path $root 'dist/OpenProjectTray-portable/*') -Destination $sandbox -Recurse
$utf8 = New-Object Text.UTF8Encoding($true)
$bridge = [IO.File]::ReadAllText((Join-Path $root 'src/Bridge.cs')).Replace('"OpenProjectTray." + WindowsIdentity.GetCurrent().User.Value', ('"OpenProjectTray.Test.' + $id + '"'))
[IO.File]::WriteAllText((Join-Path $sandbox 'Bridge.cs'), $bridge)
$csc = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
& $csc /nologo /target:library "/out:$sandbox/OpenProjectTray.Shared.dll" /r:System.Drawing.dll /r:System.Web.Extensions.dll (Join-Path $sandbox 'Bridge.cs') (Join-Path $root 'src/PluginSupport.cs')
if ($LASTEXITCODE -ne 0) { throw 'Mock bridge compilation failed' }
Copy-Item -LiteralPath (Join-Path $sandbox 'OpenProjectTray.Shared.dll') -Destination (Join-Path $sandbox 'plugin/com.openproject.tray.sdPlugin/bin/OpenProjectTray.Shared.dll') -Force
$fake = @'
function Test-OpenProjectQuick { return (Test-Path (Join-Path $script:OpTrayDir 'running')) }
function Test-OpenProjectRunning { return (Test-OpenProjectQuick) }
function Invoke-WslProcess { throw 'TEST FAILURE: real WSL path called' }
function Open-OpenProjectBrowser { }
function Start-OpenProjectPipeline {
    param([switch]$OpenBrowserWhenReady)
    [IO.File]::AppendAllText((Join-Path $script:OpTrayDir 'operations'), "start`n")
    Start-Sleep -Milliseconds 600
    [IO.File]::WriteAllText((Join-Path $script:OpTrayDir 'running'), 'yes')
    return @{Mode='MockStart';Ready=$true}
}
function Restart-OpenProjectPipeline {
    param([switch]$WithMigrate, [switch]$OpenBrowserWhenReady)
    [IO.File]::AppendAllText((Join-Path $script:OpTrayDir 'operations'), "restart-migrate`n")
    Start-Sleep -Milliseconds 800
    if (Test-Path (Join-Path $script:OpTrayDir 'fail')) { Remove-Item -LiteralPath (Join-Path $script:OpTrayDir 'running') -ErrorAction SilentlyContinue; throw 'mock migration failure' }
    return @{Mode='MockRestart';Ready=$true}
}
'@
[IO.File]::AppendAllText((Join-Path $sandbox 'OpenProject-Tray.Core.ps1'), "`r`n" + $fake, $utf8)
$tray = [IO.File]::ReadAllText((Join-Path $sandbox 'OpenProject-Tray.ps1')).Replace('Local\OpenProjectTray.Singleton', "Local\OpenProjectTray.Test.$id")
$hook = @'
function Show-Balloon { param($Title,$Text,$Icon) }
[IO.File]::WriteAllText((Join-Path $script:TrayDir 'tray.pid'), [string]$PID)
$testExit = New-Object Windows.Forms.Timer
$testExit.Interval = 100
$testExit.Add_Tick({ if (Test-Path (Join-Path $script:TrayDir 'exit')) { $testExit.Stop(); Stop-TrayApplication } })
$testExit.Start()
'@
$tray = $tray.Replace('[System.Windows.Forms.Application]::Run($script:HiddenForm)', ($hook + "`r`n[System.Windows.Forms.Application]::Run(`$script:HiddenForm)"))
[IO.File]::WriteAllText((Join-Path $sandbox 'OpenProject-Tray.ps1'), $tray, $utf8)
Add-Type -Path (Join-Path $sandbox 'OpenProjectTray.Shared.dll')
function Request([string]$command) { return ([OpenProjectTray.BridgeClient]::Request($command) | ConvertFrom-Json) }
function Wait-State([string]$state) {
    $until = (Get-Date).AddSeconds(15)
    do { try { $value = Request 'status'; if ($value.state -eq $state -and -not $value.busy) { return $value } } catch { }; Start-Sleep -Milliseconds 150 } while ((Get-Date) -lt $until)
    $err = Get-Content (Join-Path $sandbox 'logs/tray-startup-error.log') -ErrorAction SilentlyContinue
    throw "State $state not reached. $err"
}
function Launch([string]$arguments) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = Join-Path $sandbox 'OpenProjectTray.exe'
    $info.Arguments = $arguments
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.WindowStyle = 'Hidden'
    $p = [Diagnostics.Process]::Start($info)
    if (-not $p.WaitForExit(20000)) { $p.Kill(); throw 'Launcher timeout' }
    if ($p.ExitCode -ne 0) { throw 'Launcher failed' }
    $p.Dispose()
}
try {
    Launch '--background'
    $null = Wait-State 'Stopped'
    if (Test-Path (Join-Path $sandbox 'operations')) { throw 'Background launch performed an operation' }
    Write-Host 'PASS background launch is monitor-only'
    $firstPid = Get-Content (Join-Path $sandbox 'tray.pid')
    Launch ''
    $null = Wait-State 'Running'
    if ((Get-Content (Join-Path $sandbox 'operations') -Raw).Trim() -ne 'start') { throw 'Stopped did not start' }
    Write-Host 'PASS EXE starts stopped stack'
    Launch ''
    $busy = Request 'activate'
    if ($busy.result -ne 'busy') { throw 'Duplicate operation accepted' }
    $null = Wait-State 'Running'
    if ((Get-Content (Join-Path $sandbox 'tray.pid')) -ne $firstPid) { throw 'Duplicate tray process' }
    if (@(Get-Content (Join-Path $sandbox 'operations')).Count -ne 2) { throw 'Wrong operation count' }
    Write-Host 'PASS repeated EXE migrates once in same tray process'
    [IO.File]::WriteAllText((Join-Path $sandbox 'fail'),'yes')
    Launch ''
    $errorStatus = Wait-State 'Error'
    if ($errorStatus.error -notlike '*mock migration failure*') { throw 'Error not shared' }
    Write-Host 'PASS migration failure reaches tray and IPC'
    [IO.File]::WriteAllText((Join-Path $sandbox 'running'),'yes')
    Remove-Item -LiteralPath (Join-Path $sandbox 'fail')
    [IO.File]::WriteAllText((Join-Path $sandbox 'exit'),'yes')
    $old = Get-Process -Id ([int]$firstPid) -ErrorAction SilentlyContinue
    if ($old) { $null = $old.WaitForExit(5000) }
    Remove-Item -LiteralPath (Join-Path $sandbox 'exit')
    Launch ''
    $null = Wait-State 'Running'
    if ((Get-Content (Join-Path $sandbox 'operations') | Select-Object -Last 1) -ne 'restart-migrate') { throw 'Running stack was not recognized after tray restart' }
    Write-Host 'PASS closed tray recognizes running stack'
    Write-Host "Integration sandbox: $sandbox"
} finally {
    [IO.File]::WriteAllText((Join-Path $sandbox 'exit'),'yes')
    Start-Sleep -Milliseconds 500
    $pidFile = Join-Path $sandbox 'tray.pid'
    if (Test-Path $pidFile) {
        $testProcess = Get-Process -Id ([int](Get-Content $pidFile)) -ErrorAction SilentlyContinue
        if ($testProcess -and -not $testProcess.WaitForExit(3000)) { $testProcess.Kill() }
    }
}
