#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$portable = Join-Path $root 'dist/OpenProjectTray-portable'
[void][IO.Directory]::CreateDirectory($portable)
$sentinel = Join-Path $portable 'test-exclude-from-package.txt'
[IO.File]::WriteAllText($sentinel, 'This user file must never enter the installer payload.')
& (Join-Path $root 'build/Build-Release.ps1')
if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw 'Build failed' }
try {
    $archive = [IO.Compression.ZipFile]::OpenRead((Join-Path $root 'build/obj/payload.zip'))
    try { if (@($archive.Entries | Where-Object { $_.FullName -like '*test-exclude*' }).Count -gt 0) { throw 'Build packaged a personal file' } }
    finally { $archive.Dispose() }
    Write-Host 'PASS release excludes unrelated portable files'
} finally { Remove-Item -LiteralPath $sentinel }
$csc = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$obj = Join-Path $root 'build/obj'
& $csc /nologo /target:exe "/out:$obj/DesktopTests.exe" /r:System.Drawing.dll /r:System.Web.Extensions.dll /r:System.Windows.Forms.dll (Join-Path $root 'src/Bridge.cs') (Join-Path $root 'src/PluginSupport.cs') (Join-Path $PSScriptRoot 'DesktopTests.cs')
if ($LASTEXITCODE -ne 0) { throw 'Test compilation failed' }
& "$obj/DesktopTests.exe" $root
if ($LASTEXITCODE -ne 0) { throw 'Desktop tests failed' }
