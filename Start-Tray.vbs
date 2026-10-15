' Compatibility shortcut. Normal entry point is OpenProjectTray.exe.
Option Explicit
Dim sh, dir, exe, fs
Set sh = CreateObject("WScript.Shell")
Set fs = CreateObject("Scripting.FileSystemObject")
dir = fs.GetParentFolderName(WScript.ScriptFullName)
exe = dir & "\OpenProjectTray.exe"
If Not fs.FileExists(exe) Then exe = dir & "\dist\OpenProjectTray-portable\OpenProjectTray.exe"
If fs.FileExists(exe) Then
    sh.Run """" & exe & """", 0, False
Else
    MsgBox "Build the app first: powershell -File build\Build-Release.ps1", 48, "OpenProject Tray"
End If
