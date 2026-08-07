' MoviePilot Windows portable entry point.
' Runs launcher.cmd with a hidden console window, so the only visible UI is
' the tray icon started by app/main.py. ASCII-only comments on purpose.

Option Explicit

Dim shell, fso, appDir, cmdPath

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

appDir = fso.GetParentFolderName(WScript.ScriptFullName)
cmdPath = fso.BuildPath(appDir, "launcher.cmd")

If Not fso.FileExists(cmdPath) Then
    MsgBox "launcher.cmd not found:" & vbCrLf & cmdPath, vbCritical, "MoviePilot"
    WScript.Quit 1
End If

' 0 = hidden window, False = do not wait for it to finish
shell.Run """" & cmdPath & """", 0, False
