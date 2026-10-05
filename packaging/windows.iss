[Setup]
AppId={{F3725135-4137-493D-82EC-A450B722EFB6}
AppName=Vidora
AppVersion=0.1.6
DefaultDirName={localappdata}\Programs\Vidora
DefaultGroupName=Vidora
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename=Vidora-Setup-Windows-x64-0.1.6
Compression=lzma2
SolidCompression=yes
UninstallDisplayIcon={app}\local_video.exe
[Files]
Source: "..\assets\support.json"; DestDir: "{app}"; Flags: onlyifdoesntexist
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Excludes: "\support.json"; Flags: recursesubdirs createallsubdirs ignoreversion
[Icons]
Name: "{group}\Vidora"; Filename: "{app}\local_video.exe"
Name: "{userdesktop}\Vidora"; Filename: "{app}\local_video.exe"
[Run]
Filename: "{app}\local_video.exe"; Description: "Open Vidora"; Flags: nowait postinstall skipifsilent
