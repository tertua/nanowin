' Nanobot Portable - VBS Unzip Helper
' Usage: cscript unzip.vbs <zipfile> <destfolder>

Set objArgs = WScript.Arguments
If objArgs.Count < 2 Then
    WScript.Echo "Usage: cscript unzip.vbs <zipfile> <destfolder>"
    WScript.Quit 1
End If

ZipFile = objArgs(0)
DestFolder = objArgs(1)

Set fso = CreateObject("Scripting.FileSystemObject")
If Not fso.FolderExists(DestFolder) Then
    fso.CreateFolder(DestFolder)
End If

Set objShell = CreateObject("Shell.Application")
Set objZip = objShell.NameSpace(ZipFile)
Set objDest = objShell.NameSpace(DestFolder)

If Not objZip Is Nothing Then
    objDest.CopyHere objZip.Items, 256
    WScript.Echo "Extracted successfully"
Else
    WScript.Echo "Failed to open ZIP file"
    WScript.Quit 1
End If