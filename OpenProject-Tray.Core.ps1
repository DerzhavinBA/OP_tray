#Requires -Version 5.1
# OpenProject tray core (no UI). Dot-source from OpenProject-Tray.ps1 / Test-Tray.ps1.
# Save as UTF-8 with BOM for Windows PowerShell 5.1.

$ErrorActionPreference = 'Stop'

function Get-OpWslTrayDirFromPath {
    param([Parameter(Mandatory)][string]$Path)
    $drive = $Path.Substring(0, 1).ToLower()
    $rest = $Path.Substring(2).TrimStart('\').Replace('\', '/')
    return "/mnt/$drive/$rest"
}

function Get-OpSettingsDefaults {
    return [ordered]@{
        OpenProjectRoot      = '/opt/openproject'
        Distro               = 'Debian'
        LinuxUser            = 'openproject'
        Url                  = 'http://127.0.0.1'
        StartWithWindows     = $false
        AutoStartOpenProject = $false
        OpenBrowserOnStart   = $true
        ColdReadyTimeoutSec  = 180
        WarmReadyTimeoutSec  = 90
        PrepareTimeoutSec    = 300
        WslWakeTimeoutSec    = 60
        WslCommandTimeoutSec = 120
        StreamDockPluginsPath = ''
    }
}

function Get-OpSettingsPath {
    param([Parameter(Mandatory)][string]$TrayDir)
    return (Join-Path $TrayDir 'settings.json')
}

function Get-OpActivityLogDir {
    param([string]$TrayDir = $script:OpTrayDir)
    if ([string]::IsNullOrWhiteSpace($TrayDir)) { $TrayDir = $script:OpTrayDir }
    return (Join-Path $TrayDir 'logs')
}

function Get-OpActivityLogPath {
    param([string]$TrayDir = $script:OpTrayDir)
    return (Join-Path (Get-OpActivityLogDir -TrayDir $TrayDir) 'tray-activity.log')
}

function ConvertTo-OpActivityDayKey {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $dt = [datetime]::MinValue
    if ([datetime]::TryParseExact($Value, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$dt)) {
        return $dt.ToString('yyyy-MM-dd')
    }
    if ([datetime]::TryParseExact($Value, 'dd.MM.yyyy', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$dt)) {
        return $dt.ToString('yyyy-MM-dd')
    }
    return $null
}

function Format-OpActivityDayLabel {
    param([Parameter(Mandatory)][string]$DayKey)
    $dt = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($DayKey, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$dt)) {
        return $DayKey
    }
    return $dt.ToString('dd.MM.yyyy')
}

function Get-OpActivityLogLastDayFromFile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $lines = [System.IO.File]::ReadAllLines($Path, [System.Text.UTF8Encoding]::new($false))
        for ($i = $lines.Length - 1; $i -ge 0; $i--) {
            $line = $lines[$i].Trim()
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line -match '^-+$' -or $line -match '^─+\s') { continue }
            if ($line -match '^(\d{4}-\d{2}-\d{2})\s' -or $line -match '^(\d{2}\.\d{2}\.\d{4})\s') {
                $key = ConvertTo-OpActivityDayKey -Value $Matches[1]
                if ($key) { return $key }
            }
        }
    } catch { }
    return $null
}

function Write-OpActivityLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$TrayDir = $script:OpTrayDir
    )
    if ([string]::IsNullOrWhiteSpace($TrayDir)) { return }
    try {
        $dir = Get-OpActivityLogDir -TrayDir $TrayDir
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $path = Get-OpActivityLogPath -TrayDir $TrayDir
        $now = Get-Date
        $day = $now.ToString('yyyy-MM-dd')
        $dayLabel = $now.ToString('dd.MM.yyyy')
        $stamp = $now.ToString('dd.MM.yyyy HH:mm:ss')
        $text = ($Message -replace '[\r\n]+', ' ').Trim()
        if ($text.Length -gt 500) { $text = $text.Substring(0, 497) + '...' }

        $lastDay = $script:OpActivityLogLastDay
        if ([string]::IsNullOrWhiteSpace($lastDay)) {
            $lastDay = Get-OpActivityLogLastDayFromFile -Path $path
        }

        $chunk = ''
        if ($lastDay -and ($lastDay -ne $day)) {
            $chunk += "──────── $dayLabel ────────`r`n"
        } elseif (-not $lastDay -and (Test-Path -LiteralPath $path)) {
            # file exists but no parseable day — still separate if content non-empty
            $info = Get-Item -LiteralPath $path
            if ($info.Length -gt 0) {
                $chunk += "──────── $dayLabel ────────`r`n"
            }
        }
        $chunk += "$stamp  $text`r`n"
        $script:OpActivityLogLastDay = $day

        $mutex = $null
        try {
            $mutex = New-Object System.Threading.Mutex($false, 'Local\OpenProjectTrayActivityLog')
            [void]$mutex.WaitOne(3000)
            [System.IO.File]::AppendAllText($path, $chunk, [System.Text.UTF8Encoding]::new($false))
        } finally {
            if ($mutex) {
                try { $mutex.ReleaseMutex() } catch { }
                try { $mutex.Dispose() } catch { }
            }
        }
    } catch { }
}

function Format-OpActivityLogDisplay {
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $lines = $Text -split "`r?`n"
    $out = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '^─+\s+(\d{4}-\d{2}-\d{2})\s+─+$') {
            [void]$out.Add(('──────── {0} ────────' -f (Format-OpActivityDayLabel -DayKey $Matches[1])))
            continue
        }
        if ($line -match '^─+\s+(\d{2}\.\d{2}\.\d{4})\s+─+$') {
            [void]$out.Add($line)
            continue
        }
        # Legacy anonymous separators → date from the next stamped entry
        if ($line -match '^-+$' -or $line -match '^─+$') {
            $date = $null
            for ($j = $i + 1; $j -lt $lines.Count; $j++) {
                if ($lines[$j] -match '^(\d{4}-\d{2}-\d{2})\s' -or $lines[$j] -match '^(\d{2}\.\d{2}\.\d{4})\s') {
                    $key = ConvertTo-OpActivityDayKey -Value $Matches[1]
                    if ($key) { $date = Format-OpActivityDayLabel -DayKey $key }
                    break
                }
            }
            if ($date) {
                [void]$out.Add("──────── $date ────────")
            } else {
                [void]$out.Add($line)
            }
        } else {
            [void]$out.Add($line)
        }
    }
    return ($out -join "`r`n")
}

function Read-OpActivityLogText {
    param(
        [string]$TrayDir = $script:OpTrayDir,
        [int]$MaxBytes = 512000
    )
    $path = Get-OpActivityLogPath -TrayDir $TrayDir
    if (-not (Test-Path -LiteralPath $path)) {
        return "(журнал пуст — ещё нет записей)`r`n$path"
    }
    try {
        $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $len = $fs.Length
            $start = [Math]::Max(0, $len - $MaxBytes)
            if ($start -gt 0) { [void]$fs.Seek($start, [System.IO.SeekOrigin]::Begin) }
            $sr = New-Object System.IO.StreamReader($fs, [System.Text.UTF8Encoding]::new($false), $true, 4096, $true)
            $text = $sr.ReadToEnd()
            $sr.Dispose()
            if ($start -gt 0) {
                $nl = $text.IndexOf("`n")
                if ($nl -ge 0 -and $nl -lt $text.Length - 1) {
                    $text = '... (показан хвост журнала)' + "`r`n" + $text.Substring($nl + 1)
                }
            }
            return (Format-OpActivityLogDisplay -Text $text)
        } finally {
            $fs.Dispose()
        }
    } catch {
        return ("Не удалось прочитать журнал: " + $_.Exception.Message)
    }
}

function Merge-OpSettingsDefaults {
    param($Raw)
    $defaults = Get-OpSettingsDefaults
    $rawMap = ConvertTo-OpSettingsHashtable $Raw
    $out = [ordered]@{}
    foreach ($key in $defaults.Keys) {
        if ($rawMap.ContainsKey($key) -and $null -ne $rawMap[$key]) {
            $out[$key] = $rawMap[$key]
        } else {
            $out[$key] = $defaults[$key]
        }
    }
    return $out
}

function ConvertTo-OpSettingsHashtable {
    param($Obj)
    $h = @{}
    if ($null -eq $Obj) { return $h }
    if ($Obj -is [System.Collections.IDictionary]) {
        foreach ($k in @($Obj.Keys)) { $h[[string]$k] = $Obj[$k] }
        return $h
    }
    foreach ($p in $Obj.PSObject.Properties) {
        $h[$p.Name] = $p.Value
    }
    return $h
}

function Read-OpSettings {
    param([Parameter(Mandatory)][string]$TrayDir)
    $path = Get-OpSettingsPath -TrayDir $TrayDir
    $raw = $null
    if (Test-Path -LiteralPath $path) {
        try {
            $json = Get-Content -LiteralPath $path -Raw -Encoding UTF8
            if (-not [string]::IsNullOrWhiteSpace($json)) {
                $raw = ConvertTo-OpSettingsHashtable (ConvertFrom-Json $json)
            }
        } catch {
            $raw = $null
        }
    }
    return (Merge-OpSettingsDefaults -Raw $raw)
}

function Write-OpSettings {
    param(
        [Parameter(Mandatory)][string]$TrayDir,
        [Parameter(Mandatory)]$Settings
    )
    $merged = Merge-OpSettingsDefaults -Raw (ConvertTo-OpSettingsHashtable $Settings)
    Assert-OpSettingsValid -Settings $merged
    $path = Get-OpSettingsPath -TrayDir $TrayDir
    $json = ($merged | ConvertTo-Json -Depth 5)
    [System.IO.File]::WriteAllText($path, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    return $merged
}

function Assert-OpSettingsValid {
    param([Parameter(Mandatory)]$Settings)
    $s = Merge-OpSettingsDefaults -Raw (ConvertTo-OpSettingsHashtable $Settings)
    $root = [string]$s.OpenProjectRoot
    if ([string]::IsNullOrWhiteSpace($root) -or -not $root.StartsWith('/')) {
        throw 'OpenProjectRoot must be an absolute Linux path (start with /).'
    }
    foreach ($key in @('ColdReadyTimeoutSec', 'WarmReadyTimeoutSec', 'PrepareTimeoutSec', 'WslWakeTimeoutSec', 'WslCommandTimeoutSec')) {
        $n = 0
        if (-not [int]::TryParse([string]$s[$key], [ref]$n) -or $n -le 0) {
            throw "$key must be a positive integer."
        }
    }
    if ([string]::IsNullOrWhiteSpace([string]$s.Distro)) { throw 'Distro is required.' }
    if ([string]::IsNullOrWhiteSpace([string]$s.LinuxUser)) { throw 'LinuxUser is required.' }
    if ([string]::IsNullOrWhiteSpace([string]$s.Url)) { throw 'Url is required.' }
}

function Get-OpUrlParts {
    param([string]$Url = $script:OpUrl)
    try {
        $u = [Uri]$Url
        $hostName = $u.Host
        if ([string]::IsNullOrWhiteSpace($hostName)) { $hostName = '127.0.0.1' }
        $port = $u.Port
        if ($port -le 0) {
            if ($u.Scheme -eq 'https') { $port = 443 } else { $port = 80 }
        }
        return @{ Host = $hostName; Port = $port }
    } catch {
        return @{ Host = '127.0.0.1'; Port = 80 }
    }
}

function Get-OpWindowsStartupShortcutPath {
    $startup = [Environment]::GetFolderPath('Startup')
    return (Join-Path $startup 'OpenProject Tray.lnk')
}

function Test-OpWindowsStartup {
    return (Test-Path -LiteralPath (Get-OpWindowsStartupShortcutPath))
}

function Set-OpWindowsStartup {
    param(
        [Parameter(Mandatory)][string]$TrayDir,
        [Parameter(Mandatory)][bool]$Enabled
    )
    $lnkPath = Get-OpWindowsStartupShortcutPath
    $exe = Join-Path $TrayDir 'OpenProjectTray.exe'
    $target = $null
    if (Test-Path -LiteralPath $exe) {
        $target = $exe
    } else {
        throw "Не найден OpenProjectTray.exe в: $TrayDir. Используйте собранное приложение."
    }
    if ($Enabled) {
        $wsh = New-Object -ComObject WScript.Shell
        $sc = $wsh.CreateShortcut($lnkPath)
        $sc.TargetPath = $target
        if ($target -eq $exe) { $sc.Arguments = '--background --startup' }
        $sc.WorkingDirectory = $TrayDir
        $sc.WindowStyle = 7
        $sc.Description = 'OpenProject Tray Controller'
        $ico = Join-Path $TrayDir 'OpenProject.ico'
        if (Test-Path -LiteralPath $ico) {
            $sc.IconLocation = "$ico,0"
        }
        $sc.Save()
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($sc) | Out-Null
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wsh) | Out-Null
    } else {
        if (Test-Path -LiteralPath $lnkPath) {
            Remove-Item -LiteralPath $lnkPath -Force
        }
    }
}

function Initialize-OpenProjectTrayCore {
    param(
        [Parameter(Mandatory)][string]$TrayDir,
        $Settings = $null
    )
    if ($null -eq $Settings) {
        $Settings = Read-OpSettings -TrayDir $TrayDir
    } else {
        $Settings = Merge-OpSettingsDefaults -Raw (ConvertTo-OpSettingsHashtable $Settings)
    }

    $script:OpTrayDir = $TrayDir
    $script:OpWslTrayDir = Get-OpWslTrayDirFromPath -Path $TrayDir
    $script:OpSettings = $Settings
    $script:OpDistro = [string]$Settings.Distro
    $script:OpLinuxUser = [string]$Settings.LinuxUser
    $script:OpRoot = [string]$Settings.OpenProjectRoot.TrimEnd('/')
    $script:OpUrl = [string]$Settings.Url
    $parts = Get-OpUrlParts -Url $script:OpUrl
    $script:OpHttpHost = $parts.Host
    $script:OpHttpPort = [int]$parts.Port
    # WSL forwarding may listen only on IPv4. HTTPS must retain its certificate hostname.
    $loginHost = if ($script:OpHttpHost -eq 'localhost' -and ([Uri]$script:OpUrl).Scheme -eq 'http') { '127.0.0.1' } else { $script:OpHttpHost }
    $login = [UriBuilder]([Uri]$script:OpUrl)
    $login.Host = $loginHost
    $login.Path = $login.Path.TrimEnd('/') + '/login'
    $script:OpLoginUrl = $login.Uri.AbsoluteUri
    $script:OpColdReadyTimeoutSec = [int]$Settings.ColdReadyTimeoutSec
    $script:OpWarmReadyTimeoutSec = [int]$Settings.WarmReadyTimeoutSec
    $script:OpPrepareTimeoutSec = [int]$Settings.PrepareTimeoutSec
    $script:OpWslWakeTimeoutSec = [int]$Settings.WslWakeTimeoutSec
    $script:OpWslCommandTimeoutSec = [int]$Settings.WslCommandTimeoutSec
    $script:OpAutoStartOpenProject = [bool]$Settings.AutoStartOpenProject
    $script:OpOpenBrowserOnStart = [bool]$Settings.OpenBrowserOnStart
    $script:OpStartWithWindows = [bool]$Settings.StartWithWindows
    $script:OpLastPipelineMode = $null
    $script:OpLastFullStart = $false
    if (-not $script:OpActivityLogLastDay) {
        $script:OpActivityLogLastDay = $null
    }
}

function Get-OpDevLogHint {
    return 'journal:openproject'
}

function Get-OpPrepareLogHint {
    return "$($script:OpRoot)/log/tray-prepare.log"
}

function Test-OpTcpPortOpen {
    param(
        [string]$HostName = '',
        [int]$Port = 0,
        [int]$TimeoutMs = 250
    )
    if ([string]::IsNullOrWhiteSpace($HostName)) {
        $HostName = if ($script:OpHttpHost) { $script:OpHttpHost } else { '127.0.0.1' }
        if ($HostName -eq 'localhost') { $HostName = '127.0.0.1' }
    }
    if ($Port -le 0) {
        $Port = if ($script:OpHttpPort) { [int]$script:OpHttpPort } else { 80 }
    }
    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            return $false
        }
        $client.EndConnect($iar)
        return $true
    } catch {
        return $false
    } finally {
        if ($client) {
            try { $client.Close() } catch { }
        }
    }
}

# UI reads only the latest background sample.
function Test-OpenProjectQuick {
    return ($script:OpHealthCache -and $script:OpHealthCache.State -eq 'Running')
}

function Test-OpHttpReady {
    if (-not (Test-OpTcpPortOpen -TimeoutMs 400)) {
        return $false
    }
    try {
        $req = [System.Net.HttpWebRequest]::Create($script:OpLoginUrl)
        $req.Method = 'GET'
        $req.Timeout = 1000
        $req.ReadWriteTimeout = 1000
        $req.AllowAutoRedirect = $false
        $resp = $req.GetResponse()
        $code = [int]$resp.StatusCode
        $resp.Close()
        return ($code -ge 200 -and $code -lt 400)
    } catch [System.Net.WebException] {
        if ($_.Exception.Response) {
            $code = [int]$_.Exception.Response.StatusCode
            $_.Exception.Response.Close()
            return ($code -ge 200 -and $code -lt 400)
        }
        return $false
    } catch {
        return $false
    }
}

function Join-NativeArgumentList {
    param([Parameter(Mandatory)][string[]]$ArgumentList)
    # Windows PowerShell 5.1 Start-Process -ArgumentList does not quote spaced
    # args; build a CreateProcess-compatible Arguments string ourselves.
    return (($ArgumentList | ForEach-Object {
        $s = [string]$_
        if ($null -eq $_ -or $s.Length -eq 0) {
            '""'
        } elseif ($s -notmatch '[\s"]') {
            $s
        } else {
            '"' + ($s -replace '\\', '\\' -replace '"', '\"') + '"'
        }
    }) -join ' ')
}

function Invoke-WslProcess {
    param(
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [int]$TimeoutSec = 60
    )
    # Fully redirected + CreateNoWindow: no console / Windows Terminal windows.
    # Do not wrap with conhost --headless (it injects ANSI and breaks `wsl -l` parsing).
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = (Get-Command wsl.exe -ErrorAction Stop).Source
    $psi.Arguments = Join-NativeArgumentList -ArgumentList $ArgumentList
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    try {
        if (-not $p.Start()) {
            throw "Не удалось запустить процесс WSL."
        }
    } catch {
        throw "Запуск WSL не удался: $($_.Exception.Message)"
    }
    # No interactive input; closing stdin avoids console attach quirks with WT.
    try { $p.StandardInput.Close() } catch { }

    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    $ms = [Math]::Max(1000, $TimeoutSec * 1000)
    if (-not $p.WaitForExit($ms)) {
        try { $p.Kill() } catch { }
        try { [void]$outTask.Wait(500) } catch { }
        try { [void]$errTask.Wait(500) } catch { }
        throw "Таймаут ${TimeoutSec}с: wsl.exe $($ArgumentList -join ' ')"
    }
    try { [void]$outTask.Wait(5000) } catch { }
    try { [void]$errTask.Wait(5000) } catch { }
    $stdout = ''
    $stderr = ''
    try { $stdout = $outTask.Result } catch { }
    try { $stderr = $errTask.Result } catch { }
    return @{
        ExitCode = $p.ExitCode
        StdOut   = $stdout
        StdErr   = $stderr
    }
}

function ConvertFrom-OpWslListText {
    param([string]$Raw)
    if ($null -eq $Raw) { return @() }
    # wsl -l is UTF-16; when decoded as system default it often has NULs. Also strip ANSI.
    $clean = $Raw -replace '\0', '' -replace '\x1B\[[0-9;?]*[ -/]*[@-~]', '' -replace '\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)', ''
    return @($clean -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Test-WslDistroRunning {
    param([switch]$Strict)
    try {
        $r = Invoke-WslProcess -ArgumentList @('-l', '-q', '--running') -TimeoutSec 5
        if ($r.ExitCode -ne 0) {
            if ($Strict) { throw "WSL list: exit=$($r.ExitCode). $($r.StdErr) $($r.StdOut)" }
            return $false
        }
        $names = ConvertFrom-OpWslListText -Raw $r.StdOut
        return ($names -contains $script:OpDistro)
    } catch {
        if ($Strict) { throw }
        return $false
    }
}

function Ensure-WslRunning {
    if (Test-WslDistroRunning) {
        return
    }
    $r = Invoke-WslProcess -ArgumentList @('-d', $script:OpDistro, '-e', 'echo', 'OP_TRAY_WAKE') `
        -TimeoutSec $script:OpWslWakeTimeoutSec
    if ($r.ExitCode -ne 0) {
        throw "Не удалось запустить WSL ($($script:OpDistro)), код $($r.ExitCode)."
    }
    # Prefer ping over `wsl -l` (encoding quirks); allow a short settle.
    $alive = $false
    for ($i = 0; $i -lt 10; $i++) {
        if (Test-WslDistroRunning) { $alive = $true; break }
        $p = Invoke-WslProcess -ArgumentList @('-d', $script:OpDistro, '-e', 'echo', 'OP_TRAY_ALIVE') -TimeoutSec 20
        if ($p.ExitCode -eq 0 -and (($p.StdOut -replace '\0', '') -match 'OP_TRAY_ALIVE')) {
            $alive = $true
            break
        }
        Start-Sleep -Milliseconds 500
    }
    if (-not $alive) {
        throw "WSL ($($script:OpDistro)) не активен после пробуждения."
    }
}

function Invoke-WslRootChecked {
    param(
        [Parameter(Mandatory)][string]$BashCommand,
        [int]$TimeoutSec = 0
    )
    if ($TimeoutSec -le 0) { $TimeoutSec = $script:OpWslCommandTimeoutSec }
    $r = Invoke-WslProcess -ArgumentList @(
        '-d', $script:OpDistro, '-u', 'root', '--', 'bash', '-lc', $BashCommand
    ) -TimeoutSec $TimeoutSec
    if ($r.ExitCode -ne 0) {
        $hint = ($r.StdErr + $r.StdOut).Trim()
        if ($hint.Length -gt 180) { $hint = $hint.Substring(0, 180) + '...' }
        $msg = "WSL (root) код $($r.ExitCode)"
        if ($hint) { $msg += ": $hint" }
        throw $msg
    }
    return
}

function Escape-OpBashSingleQuotes {
    param([string]$Value)
    return (($Value -replace "'", "'\''"))
}

function Invoke-WslScriptChecked {
    param(
        [string]$User = $script:OpLinuxUser,
        [Parameter(Mandatory)][string]$ScriptFile,
        [int]$TimeoutSec = 0
    )
    if ($TimeoutSec -le 0) { $TimeoutSec = $script:OpWslCommandTimeoutSec }
    $linuxPath = "$($script:OpWslTrayDir)/$ScriptFile"
    $rootEsc = Escape-OpBashSingleQuotes -Value $script:OpRoot
    $pathEsc = Escape-OpBashSingleQuotes -Value $linuxPath
    $bashCmd = "export OP_ROOT='$rootEsc'; exec bash '$pathEsc'"
    $r = Invoke-WslProcess -ArgumentList @(
        '-d', $script:OpDistro, '-u', $User, '--', 'bash', '-lc', $bashCmd
    ) -TimeoutSec $TimeoutSec
    if ($r.ExitCode -ne 0) {
        $logHint = if ($ScriptFile -like '*prepare*') { Get-OpPrepareLogHint } else { Get-OpDevLogHint }
        throw "Скрипт $ScriptFile код $($r.ExitCode). Лог: $logHint"
    }
    return
}

# All package operations share the same validation and exact service namespace.
function Invoke-OpPackageCommand {
    param([Parameter(Mandatory)][ValidateSet('check','status','start','stop','migrate','pending','doctor','journal')][string]$Action,
          [int]$TimeoutSec = 30)
    $user = if ($Action -in @('start','stop','journal')) { 'root' } else { $script:OpLinuxUser }
    $path = Escape-OpBashSingleQuotes "$($script:OpWslTrayDir)/op-tray-package.sh"
    $root = Escape-OpBashSingleQuotes $script:OpRoot
    # Also bound Linux children; terminating wsl.exe alone may leave a migration alive.
    $linuxTimeout = [Math]::Max(1, $TimeoutSec - 6)
    $cmd = "export OP_ROOT='$root'; exec timeout --kill-after=5s ${linuxTimeout}s bash '$path' '$Action'"
    $r = Invoke-WslProcess -ArgumentList @('-d',$script:OpDistro,'-u',$user,'--','bash','-lc',$cmd) -TimeoutSec $TimeoutSec
    if ($r.ExitCode -ne 0) {
        $detail = ($r.StdErr + "`n" + $r.StdOut).Trim()
        if ($detail.Length -gt 1500) { $detail = $detail.Substring($detail.Length - 1500) }
        Write-OpActivityLog -Message "Package ${Action}: exit=$($r.ExitCode) $detail"
        throw "OpenProject package ${Action}: exit=$($r.ExitCode). $detail"
    }
    return $r.StdOut.Trim()
}

function Update-OpPackagedSettings {
    # Called only from a worker, after confirmation of the actual package installation.
    if ([string]$script:OpSettings.Url -cnotin @('http://localhost:3000', 'http://localhost')) { return $false }
    $null = Invoke-OpPackageCommand -Action check
    $path = Get-OpSettingsPath $script:OpTrayDir
    if (Test-Path -LiteralPath $path) {
        $backup = $path + '.before-package-' + [Guid]::NewGuid().ToString('N') + '.bak'
        Copy-Item -LiteralPath $path -Destination $backup -ErrorAction Stop
    }
    $next = Read-OpSettings $script:OpTrayDir
    if ([string]$next.Url -cnotin @('http://localhost:3000', 'http://localhost')) { return $false }
    $next.Url = 'http://127.0.0.1'
    $next = Write-OpSettings -TrayDir $script:OpTrayDir -Settings $next
    Initialize-OpenProjectTrayCore -TrayDir $script:OpTrayDir -Settings $next
    Write-OpActivityLog -Message 'Настройки пакетной установки: адрес изменён на http://127.0.0.1; сохранена резервная копия.'
    return $true
}

function Get-OpPackageHealth {
    try {
        # Monitoring never wakes a stopped distro.
        if (-not (Test-WslDistroRunning -Strict)) { return @{State='Stopped'; ActiveServices=$false; Error=''} }
        $status = Invoke-OpPackageCommand -Action status -TimeoutSec 15
        if ($status -eq 'STOPPED') { return @{State='Stopped'; ActiveServices=$false; Error=''} }
        if ($status -ne 'RUNNING') { return @{State='Error'; ActiveServices=$true; Error=$status} }
        if (-not (Test-OpHttpReady)) { return @{State='Error'; ActiveServices=$true; Error="HTTP: $($script:OpLoginUrl) не готов"} }
        return @{State='Running'; ActiveServices=$true; Error=''}
    } catch { return @{State='Error'; ActiveServices=$false; Error=$_.Exception.Message} }
}

function Test-OpenProjectRunning { return ((Get-OpPackageHealth).State -eq 'Running') }

function Start-PostgresReady {
    Ensure-WslRunning
    $null = Invoke-OpPackageCommand -Action check
    Invoke-WslRootChecked -BashCommand 'service postgresql start >/dev/null && pg_isready -q' -TimeoutSec 60
}

function Start-OpenProjectService {
    Start-PostgresReady
    $null = Invoke-OpPackageCommand -Action start -TimeoutSec $script:OpWslCommandTimeoutSec
}

function Stop-OpenProjectService {
    Ensure-WslRunning
    $null = Invoke-OpPackageCommand -Action stop -TimeoutSec $script:OpWslCommandTimeoutSec
}

function Invoke-OpenProjectPrepare {
    Start-PostgresReady
    $null = Invoke-OpPackageCommand -Action migrate -TimeoutSec $script:OpPrepareTimeoutSec
}

function Wait-OpenProjectReady {
    param([int]$TimeoutSec = 90)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    do {
        if (Test-OpenProjectRunning) { return $true }
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Open-OpenProjectBrowser {
    param([string]$Url = '')
    if ([string]::IsNullOrWhiteSpace($Url)) { $Url = $script:OpUrl }
    Start-Process $Url
}

function Get-OpWslUncPath {
    param([Parameter(Mandatory)][string]$LinuxPath)
    $norm = $LinuxPath.Trim().Replace('/', '\').TrimStart('\')
    return "\\wsl$\$($script:OpDistro)\$norm"
}

function Get-OpDevLogUncPath {
    return (Get-OpWslUncPath -LinuxPath "$(Get-OpDevLogHint)")
}

function Get-OpPrepareLogUncPath {
    return (Get-OpWslUncPath -LinuxPath "$(Get-OpPrepareLogHint)")
}

function Read-OpWslTextFile {
    param(
        [Parameter(Mandatory)][string]$LinuxPath,
        [int]$TailLines = 200,
        [int]$TimeoutSec = 30
    )
    if ($LinuxPath -eq 'journal:openproject') {
        Ensure-WslRunning
        return (Invoke-OpPackageCommand -Action journal -TimeoutSec $TimeoutSec)
    }
    $unc = Get-OpWslUncPath -LinuxPath $LinuxPath
    if (Test-Path -LiteralPath $unc) {
        try {
            $lines = Get-Content -LiteralPath $unc -Tail $TailLines -ErrorAction Stop
            return ($lines -join "`r`n")
        } catch { }
    }
    $pathEsc = Escape-OpBashSingleQuotes -Value $LinuxPath
    $cmd = "if [ -f '$pathEsc' ]; then tail -n $TailLines -- '$pathEsc'; else echo '(файл не найден: $pathEsc)'; fi"
    Ensure-WslRunning
    $r = Invoke-WslProcess -ArgumentList @(
        '-d', $script:OpDistro, '-u', $script:OpLinuxUser, '--', 'bash', '-lc', $cmd
    ) -TimeoutSec $TimeoutSec
    $out = ($r.StdOut + $r.StdErr).TrimEnd()
    if ([string]::IsNullOrWhiteSpace($out)) { $out = '(пусто)' }
    return $out
}

function Open-OpWslLogInNotepad {
    param([Parameter(Mandatory)][string]$LinuxPath)
    $unc = if ($LinuxPath -eq 'journal:openproject') { '' } else { Get-OpWslUncPath -LinuxPath $LinuxPath }
    if ($unc -and (Test-Path -LiteralPath $unc)) {
        Start-Process notepad.exe -ArgumentList $unc
        return
    }
    $text = Read-OpWslTextFile -LinuxPath $LinuxPath -TailLines 2000
    $dir = Get-OpActivityLogDir -TrayDir $script:OpTrayDir
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $name = if ($LinuxPath -eq 'journal:openproject') { 'openproject-services.log' } else { [System.IO.Path]::GetFileName($LinuxPath) }
    if ([string]::IsNullOrWhiteSpace($name)) { $name = 'wsl-log.txt' }
    $tmp = Join-Path $dir ("view-" + $name)
    [System.IO.File]::WriteAllText($tmp, $text + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    Start-Process notepad.exe -ArgumentList $tmp
}

function Start-OpWslLogFollow {
    param([Parameter(Mandatory)][string]$LinuxPath)
    Ensure-WslRunning
    $pathEsc = Escape-OpBashSingleQuotes -Value $LinuxPath
    $inner = "if [ -f '$pathEsc' ]; then echo Following: $pathEsc; tail -n 50 -f -- '$pathEsc'; else echo 'File not found: $pathEsc'; exec bash -l; fi"
    $user = $script:OpLinuxUser
    if ($LinuxPath -eq 'journal:openproject') {
        $inner = "exec journalctl --no-pager -n 50 -f -u 'openproject*.service'"
        $user = 'root'
    }
    $wt = Get-Command wt.exe -ErrorAction SilentlyContinue
    if ($wt) {
        $arg = Join-NativeArgumentList -ArgumentList @(
            'new-tab', '--', 'wsl.exe', '-d', $script:OpDistro, '-u', $user, '--', 'bash', '-lc', $inner
        )
        Start-Process -FilePath $wt.Source -ArgumentList $arg -WindowStyle Hidden
        return
    }
    $arg = Join-NativeArgumentList -ArgumentList @(
        '-d', $script:OpDistro, '-u', $user, '--', 'bash', '-lc', $inner
    )
    Start-Process -FilePath 'wsl.exe' -ArgumentList $arg -WindowStyle Hidden
}

function Open-OpProjectTerminal {
    Ensure-WslRunning
    $rootEsc = Escape-OpBashSingleQuotes -Value $script:OpRoot
    $inner = "cd '$rootEsc' && exec bash -l"
    $wt = Get-Command wt.exe -ErrorAction SilentlyContinue
    if ($wt) {
        $arg = Join-NativeArgumentList -ArgumentList @(
            'new-tab', '--', 'wsl.exe', '-d', $script:OpDistro, '-u', $script:OpLinuxUser, '--cd', $script:OpRoot
        )
        Start-Process -FilePath $wt.Source -ArgumentList $arg
        return
    }
    $arg = Join-NativeArgumentList -ArgumentList @(
        '-d', $script:OpDistro, '-u', $script:OpLinuxUser, '--', 'bash', '-lc', $inner
    )
    Start-Process -FilePath 'wsl.exe' -ArgumentList $arg
}

function Invoke-OpDoctorCheck {
    try {
        Ensure-WslRunning
        $report = Invoke-OpPackageCommand -Action doctor -TimeoutSec 60
        $health = Get-OpPackageHealth
        return @{Ok=($health.State -ne 'Error'); Ready=$true; Mode='Doctor'; Report=($report + "`r`nHTTP/services: " + $health.State + ' ' + $health.Error)}
    } catch { return @{Ok=$false; Ready=$true; Mode='Doctor'; Report=('[FAIL] ' + $_.Exception.Message)} }
}

function Get-OpPendingMigrationCount {
    Ensure-WslRunning
    $raw = Invoke-OpPackageCommand -Action pending -TimeoutSec $script:OpPrepareTimeoutSec
    $n = 0
    if (-not [int]::TryParse($raw.Trim(), [ref]$n) -or $n -lt 0) { throw "Не удалось разобрать pending count: $raw" }
    return @{Pending=$n; Ready=$true; Mode='PendingMigrate'; Report="Pending migrations: $n"}
}

function Start-OpenProjectPipeline {
    param([switch]$OpenBrowserWhenReady)

    $wasRunning = Test-WslDistroRunning
    Ensure-WslRunning
    $null = Update-OpPackagedSettings
    if (Test-OpenProjectRunning) {
        $script:OpLastPipelineMode = 'Fast'
        $script:OpLastFullStart = $false
        if ($OpenBrowserWhenReady) { Open-OpenProjectBrowser }
        return @{ Mode = 'Fast'; FullStart = $false; Ready = $true }
    }

    if ($wasRunning) {
        $script:OpLastPipelineMode = 'Warm'
        $timeout = $script:OpWarmReadyTimeoutSec
    } else {
        $script:OpLastPipelineMode = 'Cold'
        $timeout = $script:OpColdReadyTimeoutSec
    }

    Ensure-WslRunning
    Start-OpenProjectService
    $script:OpLastFullStart = $true
    $ready = Wait-OpenProjectReady -TimeoutSec $timeout
    if (-not $ready) {
        throw "Нет ответа :$($script:OpHttpPort) за $timeout с. Журнал: journalctl -u openproject*.service"
    }
    if ($OpenBrowserWhenReady) { Open-OpenProjectBrowser }
    return @{ Mode = $script:OpLastPipelineMode; FullStart = $true; Ready = $true }
}

function Restart-OpenProjectPipeline {
    param(
        [switch]$OpenBrowserWhenReady,
        [switch]$WithMigrate
    )
    Ensure-WslRunning
    $null = Update-OpPackagedSettings
    Stop-OpenProjectService
    if ($WithMigrate) {
        Invoke-OpenProjectPrepare
    }
    Start-OpenProjectService
    $script:OpLastPipelineMode = if ($WithMigrate) { 'RestartMigrate' } else { 'Restart' }
    $script:OpLastFullStart = $true
    $timeout = $script:OpWarmReadyTimeoutSec
    $ready = Wait-OpenProjectReady -TimeoutSec $timeout
    if (-not $ready) {
        throw "После рестарта нет :$($script:OpHttpPort) за $timeout с. Журнал: journalctl -u openproject*.service"
    }
    if ($OpenBrowserWhenReady) { Open-OpenProjectBrowser }
    return @{ Mode = $script:OpLastPipelineMode; FullStart = $true; Ready = $true }
}
