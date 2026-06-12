#define MyAppName "Patty"
#define MyAppVersion "0.1.0"
#define MyAppPublisher "Aspen Feltner"
#define MyAppURL "https://github.com/Aspenini/patty"
#define MyAppExeName "pattyw.exe"
#define MyAppId "{{D8D05D1B-1F3B-4D67-92A6-78228D645EB7}"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
AppUpdatesURL={#MyAppURL}/releases
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} installer
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}
VersionInfoVersion={#MyAppVersion}.0
SetupArchitecture=x64
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\Patty
DefaultGroupName=Patty
DisableProgramGroupPage=yes
UsePreviousAppDir=yes
UsePreviousTasks=yes
AllowNoIcons=yes
LicenseFile=..\LICENSE
SetupIconFile=..\icons\icon.ico
UninstallDisplayIcon={app}\icons\icon.ico
UninstallDisplayName={#MyAppName}
OutputDir=..\dist
OutputBaseFilename=patty-{#MyAppVersion}-windows-x86_64-setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern dynamic
CloseApplications=yes
RestartApplications=no
SetupLogging=yes
UninstallLogging=yes
RedirectionGuard=yes
TimeStampsInUTC=yes

[Tasks]
Name: autostart; Description: "Start Patty automatically when I sign in"; GroupDescription: "Startup:"
Name: desktopicon; Description: "Create a &desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked

[Files]
Source: "..\bin\patty.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\bin\pattyw.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\bin\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\examples\*"; DestDir: "{app}\examples"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\icons\*"; DestDir: "{app}\icons"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\Patty"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\icons\icon.ico"; AppUserModelID: "Aspenini.Patty"
Name: "{autodesktop}\Patty"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\icons\icon.ico"; AppUserModelID: "Aspenini.Patty"; Tasks: desktopicon

[Run]
Filename: "{app}\patty.exe"; Parameters: "install"; WorkingDir: "{app}"; StatusMsg: "Enabling automatic startup..."; Flags: runhidden; Tasks: autostart
Filename: "{app}\patty.exe"; Parameters: "uninstall"; WorkingDir: "{app}"; StatusMsg: "Disabling automatic startup..."; Flags: runhidden; Tasks: not autostart
Filename: "{app}\{#MyAppExeName}"; Description: "Launch Patty"; WorkingDir: "{app}"; Flags: postinstall nowait skipifsilent

[UninstallRun]
Filename: "{app}\patty.exe"; Parameters: "uninstall"; WorkingDir: "{app}"; Flags: runhidden skipifdoesntexist; RunOnceId: "RemovePattyAutostart"
