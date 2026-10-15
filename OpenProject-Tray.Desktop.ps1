# Desktop integration. Loaded only by the tray UI.
Add-Type -Path (Join-Path $script:TrayDir 'OpenProjectTray.Shared.dll')

function Publish-OpDesktopStatus {
    if ($script:DesktopBridge) {
        $script:DesktopBridge.Publish($script:TrayState, $script:Busy, [string]$script:BgActionName, [string]$script:LastErrorTip)
    }
}

function Invoke-OpActivate {
    if ($script:Busy) { return }
    $action = [OpenProjectTray.ActivationPolicy]::Action((Test-OpenProjectQuick), $false)
    if ($action -eq 'restart-migrate') { Invoke-UiRestartMigrate } else { Invoke-UiStart }
}

function Start-OpDesktopBridge {
    $script:DesktopBridge = New-Object OpenProjectTray.BridgeServer
    Publish-OpDesktopStatus
    $script:DesktopTimer = New-Object System.Windows.Forms.Timer
    $script:DesktopTimer.Interval = 100
    $script:DesktopTimer.Add_Tick({
        try {
            if ($script:DesktopBridge.TakeActivation()) { Invoke-OpActivate }
        } catch {
            Set-TrayVisualState -State 'Error' -Tip ('OpenProject: ' + $_.Exception.Message)
            Write-OpActivityLog -Message ('Команда приложения: ' + $_.Exception.Message)
        } finally { Publish-OpDesktopStatus }
    })
    $script:DesktopTimer.Start()
}

function Show-OpPluginDialog {
    $settings = Read-OpSettings -TrayDir $script:TrayDir
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Плагин StreamDock'
    $form.ClientSize = New-Object System.Drawing.Size(640, 235)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $label = New-Object System.Windows.Forms.Label
    $label.Text = 'Папка plugins — приложение создаст внутри собственную папку плагина'
    $label.SetBounds(16, 16, 610, 24)
    $box = New-Object System.Windows.Forms.TextBox
    $box.SetBounds(16, 48, 452, 26)
    $box.Text = [string]$settings.StreamDockPluginsPath
    if (-not $box.Text) { $box.Text = Join-Path $env:APPDATA 'HotSpot\StreamDock\plugins' }
    $browse = New-Object System.Windows.Forms.Button
    $browse.Text = 'Выбрать папку…'
    $browse.SetBounds(480, 46, 144, 30)
    $status = New-Object System.Windows.Forms.Label
    $status.SetBounds(16, 90, 608, 78)
    $install = New-Object System.Windows.Forms.Button
    $install.Text = 'Установить / обновить'
    $install.SetBounds(16, 185, 220, 32)
    $form.Controls.AddRange(@($label, $box, $browse, $status, $install))
    $refresh = {
        $manifest = Join-Path $box.Text 'com.openproject.tray.sdPlugin\manifest.json'
        $status.Text = if (Test-Path -LiteralPath $manifest) { 'Плагин найден. Можно обновить; настройки кнопок сохранятся.' } else { 'Плагин ещё не установлен в выбранной папке.' }
    }.GetNewClosure()
    $box.Add_TextChanged($refresh)
    & $refresh
    $browse.Add_Click({
        $picker = New-Object System.Windows.Forms.FolderBrowserDialog
        $picker.Description = 'Выберите родительскую папку plugins для StreamDock'
        $picker.SelectedPath = $box.Text
        if ($picker.ShowDialog($form) -eq 'OK') { $box.Text = $picker.SelectedPath }
        $picker.Dispose()
    }.GetNewClosure())
    $trayDir = $script:TrayDir
    $install.Add_Click({
        $install.Enabled = $false
        try {
            $package = Join-Path $trayDir 'plugin\com.openproject.tray.sdPlugin'
            $target = [OpenProjectTray.PluginInstaller]::Install($package, $box.Text.Trim(), (Join-Path $trayDir 'OpenProjectTray.exe'))
            $next = Read-OpSettings -TrayDir $trayDir
            $next.StreamDockPluginsPath = $box.Text.Trim()
            $null = Write-OpSettings -TrayDir $trayDir -Settings $next
            $status.Text = "Установлено: $target`r`nПерезапустите StreamDock и перетащите действие OpenProject на кнопку."
        } catch {
            $status.Text = 'Установка не выполнена: ' + $_.Exception.GetBaseException().Message
            [System.Windows.Forms.MessageBox]::Show($form, ($status.Text + "`r`nЕсли файлы заняты, закройте StreamDock и повторите установку."), 'Плагин StreamDock', 'OK', 'Error') | Out-Null
        } finally { $install.Enabled = $true }
    }.GetNewClosure())
    $null = $form.ShowDialog($script:HiddenForm)
    $form.Dispose()
}
