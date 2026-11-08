#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
[Setup]
AppId={{788499DD-624E-4E5E-91CB-8A3DB39DBB67}
AppName=EquipmentManager
AppVersion={#AppVersion}
AppPublisher=EquipmentManager
DefaultDirName={localappdata}\Programs\EquipmentManager
DefaultGroupName=EquipmentManager
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename=EquipmentManager-{#AppVersion}-windows-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\EquipmentManager.exe
CloseApplications=yes
RestartApplications=no
[Languages]
Name: "vietnamese"; MessagesFile: "Vietnamese.isl"
[Tasks]
Name: "desktopicon"; Description: "Tạo biểu tượng trên màn hình"; Flags: unchecked
[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "unregister-reminder.ps1"; DestDir: "{app}"; Flags: ignoreversion
[Icons]
Name: "{group}\EquipmentManager"; Filename: "{app}\EquipmentManager.exe"; AppUserModelID: "CAH.EquipmentManager"
Name: "{autodesktop}\EquipmentManager"; Filename: "{app}\EquipmentManager.exe"; Tasks: desktopicon
[Run]
Filename: "{app}\EquipmentManager.exe"; Description: "Mở EquipmentManager"; Flags: nowait postinstall skipifsilent
[UninstallRun]
Filename: "powershell.exe"; Parameters: "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\unregister-reminder.ps1"""; Flags: runhidden waituntilterminated
