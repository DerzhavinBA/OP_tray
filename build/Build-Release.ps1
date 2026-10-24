#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { throw '.NET Framework 4.x compiler not found' }
$obj = Join-Path $PSScriptRoot 'obj'
$dist = Join-Path $root 'dist'
$portable = Join-Path $dist 'OpenProjectTray-portable'
foreach ($path in @($obj, $dist, $portable)) { [void][IO.Directory]::CreateDirectory($path) }
function Compile([string[]]$Arguments) {
    & $csc /nologo /optimize+ @Arguments
    if ($LASTEXITCODE -ne 0) { throw 'C# compilation failed' }
}
$shared = Join-Path $portable 'OpenProjectTray.Shared.dll'
Compile @('/target:library', "/out:$shared", '/r:System.Drawing.dll', '/r:System.Web.Extensions.dll', (Join-Path $root 'src/Bridge.cs'), (Join-Path $root 'src/PluginSupport.cs'))
Compile @('/target:winexe', "/out:$portable/OpenProjectTray.exe", "/win32icon:$root/OpenProject.ico", "/r:$shared", '/r:System.Windows.Forms.dll', (Join-Path $root 'src/Launcher.cs'))
$plugin = Join-Path $portable 'plugin/com.openproject.tray.sdPlugin'
[void][IO.Directory]::CreateDirectory((Join-Path $plugin 'bin'))
Copy-Item -Path (Join-Path $root 'plugin/com.openproject.tray.sdPlugin/*') -Destination $plugin -Recurse -Force
Copy-Item -LiteralPath $shared -Destination (Join-Path $plugin 'bin/OpenProjectTray.Shared.dll') -Force
Copy-Item -LiteralPath (Join-Path $root 'OpenProject.ico') -Destination (Join-Path $plugin 'static/OpenProject.ico') -Force
Compile @('/target:winexe', "/out:$plugin/bin/OpenProjectPlugin.exe", "/win32icon:$root/OpenProject.ico", "/r:$shared", '/r:System.Web.Extensions.dll', (Join-Path $root 'src/Plugin.cs'))
Add-Type -AssemblyName System.Drawing
Add-Type -Path $shared
$bitmap = [OpenProjectTray.ButtonRenderer]::LoadLogo((Join-Path $root 'OpenProject.ico'))
$bitmap.Save((Join-Path $plugin 'static/icon.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$bitmap.Dispose()
$runtimeFiles = @('OpenProject-Tray.ps1','OpenProject-Tray.Core.ps1','OpenProject-Tray.Desktop.ps1','OpenProject.ico','op-tray-package.sh','op-tray-start.sh','op-tray-stop.sh','op-tray-prepare.sh','op-tray-doctor.sh','settings.example.json','README.md')
foreach ($file in $runtimeFiles) {
    Copy-Item -LiteralPath (Join-Path $root $file) -Destination $portable -Force
}
$setupRefs = @('/r:System.Windows.Forms.dll','/r:System.Drawing.dll','/r:System.IO.Compression.dll','/r:System.IO.Compression.FileSystem.dll','/r:Microsoft.CSharp.dll','/r:System.Web.Extensions.dll')
Compile (@('/target:winexe','/define:UNINSTALL',"/out:$portable/Uninstall.exe", "/win32icon:$root/OpenProject.ico") + $setupRefs + @((Join-Path $root 'src/Setup.cs')))
$pluginFiles = @('manifest.json','bin/OpenProjectPlugin.exe','bin/OpenProjectTray.Shared.dll','static/OpenProject.ico','static/icon.png','static/property_inspector.html','static/inspector.js')
$files = $runtimeFiles + @('OpenProjectTray.exe','OpenProjectTray.Shared.dll','Uninstall.exe') + @($pluginFiles | ForEach-Object { 'plugin/com.openproject.tray.sdPlugin/' + $_ })
[IO.File]::WriteAllLines((Join-Path $portable 'installed-files.txt'), @($files) + 'installed-files.txt')
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
$zip = Join-Path $obj 'payload.zip'
# Rebuild only the generated ZIP, never delete a portable user's settings or logs.
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
$archive = [IO.Compression.ZipFile]::Open($zip, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in @($files) + 'installed-files.txt') {
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, (Join-Path $portable $file), $file.Replace('\','/'))
    }
} finally { $archive.Dispose() }
Compile (@('/target:winexe',"/out:$dist/OpenProjectTray-Setup.exe", "/win32icon:$root/OpenProject.ico", "/resource:$zip,payload.zip") + $setupRefs + @((Join-Path $root 'src/Setup.cs')))
Write-Host "Built: $portable"
Write-Host "Built: $dist/OpenProjectTray-Setup.exe"
