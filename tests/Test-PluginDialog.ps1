#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$script:TrayDir = Join-Path $root ('build/obj/dialog-' + [Guid]::NewGuid().ToString('N'))
Copy-Item -LiteralPath (Join-Path $root 'dist/OpenProjectTray-portable') -Destination $script:TrayDir -Recurse
. (Join-Path $script:TrayDir 'OpenProject-Tray.Core.ps1')
. (Join-Path $script:TrayDir 'OpenProject-Tray.Desktop.ps1')
$script:HiddenForm = New-Object Windows.Forms.Form
$script:target = Join-Path $script:TrayDir 'Selected plugins'
$script:dialogResult = ''
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 250
$timer.Add_Tick({
    foreach ($form in @([Windows.Forms.Application]::OpenForms)) {
        if ($form.Controls.Count -ne 5) { continue }
        $timer.Stop()
        $box = @($form.Controls | Where-Object { $_ -is [Windows.Forms.TextBox] })[0]
        $box.Text = $script:target
        $button = @($form.Controls | Where-Object { $_ -is [Windows.Forms.Button] -and $_.Width -eq 220 })[0]
        $button.PerformClick()
        $script:dialogResult = @($form.Controls | Where-Object { $_ -is [Windows.Forms.Label] -and $_.Height -eq 78 })[0].Text
        $form.Close()
    }
})
try {
    $timer.Start()
    Show-OpPluginDialog
    if (-not (Test-Path (Join-Path $script:target 'com.openproject.tray.sdPlugin/manifest.json'))) { throw "Dialog installation failed: $script:dialogResult" }
    $saved = Read-OpSettings -TrayDir $script:TrayDir
    if ($saved.StreamDockPluginsPath -ne $script:target) { throw 'Selected folder was not saved' }
    Write-Host 'PASS real plugin dialog installs package and remembers folder'
} finally { $timer.Dispose(); $script:HiddenForm.Dispose() }
