#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$obj = Join-Path $root 'build/obj'
$source = [IO.File]::ReadAllText((Join-Path $root 'src/Setup.cs')).Replace('Registry.CurrentUser', 'FakeRegistry.CurrentUser').Replace('Environment.GetFolderPath', 'TestFolders.GetFolderPath')
[IO.File]::WriteAllText((Join-Path $obj 'SetupUnderTest.cs'), $source)
$csc = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
& $csc /nologo /target:exe /main:SetupTests "/out:$obj/SetupTests.exe" "/resource:$obj/payload.zip,payload.zip" /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.IO.Compression.dll /r:System.IO.Compression.FileSystem.dll /r:Microsoft.CSharp.dll /r:System.Web.Extensions.dll (Join-Path $obj 'SetupUnderTest.cs') (Join-Path $PSScriptRoot 'SetupTests.cs')
if ($LASTEXITCODE -ne 0) { throw 'Setup test compilation failed' }
& "$obj/SetupTests.exe" $root
if ($LASTEXITCODE -ne 0) { throw 'Setup tests failed' }
