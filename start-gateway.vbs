' ==========================================================
'  nanobot-gateway.vbs - Direct PowerShell Launcher
'  NO cmd.exe involved at all
' ==========================================================

Option Explicit

Dim fso, shell, scriptDir, psScript

Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

' Resolve script directory
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
psScript = scriptDir & "\scripts\nanobot-gateway.ps1"

' Validate
If Not fso.FileExists(psScript) Then
    MsgBox "scripts\nanobot-gateway.ps1 not found!" & vbCrLf & vbCrLf & _
           "Path: " & psScript & vbCrLf & vbCrLf & _
           "Run setup.bat first.", _
           vbCritical, "NanoBot Gateway"
    WScript.Quit 1
End If

' Check PowerShell exists
If Not fso.FileExists(shell.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe")) Then
    MsgBox "PowerShell not found!" & vbCrLf & vbCrLf & _
           "Windows PowerShell 5.1+ is required.", _
           vbCritical, "NanoBot Gateway"
    WScript.Quit 1
End If

' Launch PowerShell directly - bypasses cmd.exe entirely
' Window style: 1=Normal, 0=Hidden (for background mode)
Dim cmd
cmd = "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File """ & psScript & """"

' Run and wait (True = synchronous)
Dim exitCode
exitCode = shell.Run(cmd, 1, True)

WScript.Quit exitCode