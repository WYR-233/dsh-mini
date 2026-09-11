; dsh-mini installer for DeepSeek Harness Mini
; Build:  ISCC.exe installer\dsh-mini.iss   (from the repo root)
; Input:  the stage\ folder produced by scripts\stage.ps1
;
; Design goals:
;   - single setup.exe, wizard pages, ChineseSimplified UI
;   - installs to the user's LocalAppData (no admin rights needed) so the
;     tray app can write its data (home\, caches) next to the exe
;   - desktop icon + start menu icon + optional run-after-install

#define MyAppName "DeepSeek Harness Mini"
; Package (dsh-mini) version. Override from the command line when cutting a
; release:  ISCC.exe /DMyAppVersion=0.1.2 installer\dsh-mini.iss
#ifndef MyAppVersion
  #define MyAppVersion "0.1.1"
#endif
; Bundled dsh kernel, shown on the wizard and in the installed marker.
#ifndef DshVersion
  #define DshVersion "0.1.5-rc.1"
#endif
#define MyAppPublisher "WYR-233"
#define MyAppURL "https://github.com/WYR-233/dsh-mini"
#define MyAppExeName "DshMini.exe"

[Setup]
AppId={{B7E4F6A2-9C31-4D7E-8A0F-2D5E9C1B4A60}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion} (dsh {#DshVersion})
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={localappdata}\DeepSeekHarnessMini
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
DisableDirPage=no
DisableWelcomePage=no
PrivilegesRequired=lowest
OutputDir=..\release
OutputBaseFilename=DeepSeekHarnessMini-Setup-v{#MyAppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=..\assets\welcome.ico
UninstallDisplayIcon={app}\uninstall.ico
WizardImageFile=..\assets\wizard-whale.bmp
WizardSmallImageFile=..\assets\wizard-small.bmp
LicenseFile=LICENSE_ZH.txt
VersionInfoVersion={#MyAppVersion}
VersionInfoDescription={#MyAppName} installer
CloseApplications=no
RestartApplications=no

[Languages]
Name: "chinesesimplified"; MessagesFile: "lang\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "runafter"; Description: "安装完成后立即启动 {#MyAppName}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce

[Files]
Source: "..\stage\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion; Excludes: "home\*"
Source: "..\stage\home\*"; DestDir: "{app}\home"; Flags: recursesubdirs createallsubdirs onlyifdoesntexist
Source: "..\assets\uninstall.ico"; DestDir: "{app}"
Source: "..\assets\cry.bmp"; DestDir: "{app}"
Source: "..\assets\bye.bmp"; DestDir: "{app}"
; NOTE: don't use wildcard exclusions; stage\ is already clean by construction.

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\whale-desktop.ico"
Name: "{group}\卸载 {#MyAppName}"; Filename: "{uninstallexe}"; IconFilename: "{app}\uninstall.ico"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\whale-desktop.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent; Tasks: runafter

[UninstallDelete]
; runtime-generated dirs and files (not in the install manifest)
Type: filesandordirs; Name: "{app}\.temp"
Type: filesandordirs; Name: "{app}\.npm-cache"
Type: filesandordirs; Name: "{app}\backups"
Type: filesandordirs; Name: "{app}\home"
Type: files; Name: "{app}\.tray.log"

[Code]
// Pale-blue tint for the wizard so it matches the wizard art.
procedure InitializeWizard();
var
  C: TColor;
begin
  C := $FBF4EA;             // BGR of RGB(234,244,251) pale blue
  WizardForm.Color := C;
  WizardForm.MainPanel.Color := C;
  WizardForm.InnerPage.Color := C;
  WizardForm.ReadyMemo.Color := C;
  WizardForm.LicenseMemo.Color := clWhite;
end;

// Stop a running install right before file copying (ssInstall), so files
// are not locked. NOTE: {app} is not expanded in InitializeSetup or
// InitializeWizard - it becomes available only at install time.
procedure CurStepChanged(CurStep: TSetupStep);
var
  ErrCode: Integer;
  AppExe: String;
begin
  if CurStep = ssInstall then
  begin
    AppExe := ExpandConstant('{app}\DshMini.exe');
    if FileExists(AppExe) then
    begin
      Exec(AppExe, '--stop', '', SW_HIDE, ewWaitUntilTerminated, ErrCode);
      Exec('taskkill.exe', '/F /IM DshMini.exe', '', SW_HIDE, ewWaitUntilTerminated, ErrCode);
      Sleep(600);
    end;
  end;
end;

// ---------- uninstall ceremony ----------

procedure DecorateDialog(F: TForm; BmpFile: String; Msg: String);
var
  Img: TBitmapImage;
  Lbl: TLabel;
begin
  // NOTE: ExtractTemporaryFile is NOT available during uninstall; the
  // BMPs are installed into {app} and read from there instead.
  Img := TBitmapImage.Create(F);
  Img.Parent := F;
  Img.Left := 12; Img.Top := 12; Img.Width := 200; Img.Height := 200;
  Img.Stretch := True;
  Img.Bitmap.LoadFromFile(ExpandConstant('{app}\' + BmpFile));

  Lbl := TLabel.Create(F);
  Lbl.Parent := F;
  Lbl.Left := 232; Lbl.Top := 20;
  Lbl.AutoSize := False;   // keep AutoSize ON and every line wraps to 1-2 chars
  Lbl.WordWrap := True;
  Lbl.Width := 320;
  Lbl.Height := 200;
  Lbl.Caption := Msg;
end;

function ShowUninstallConfirm(): Boolean;
var
  F: TForm;
  BtnYes, BtnNo: TButton;
begin
  Result := False;
  F := TForm.Create(nil);
  try
    F.Caption := '真的要卸载 DeepSeek Harness Mini 吗?';
    F.ClientWidth := 560;
    F.ClientHeight := 320;
    F.Position := poScreenCenter;
    F.BorderStyle := bsDialog;
    DecorateDialog(F, 'cry.bmp', '呜呜...真的要走吗?' + #13#10 +
      '卸载后,鲸鱼娘会把你的对话记录、' + #13#10 +
      '设置和所有回忆全部打包带走,找不回来的...');
    BtnNo := TButton.Create(F);
    BtnNo.Parent := F;
    BtnNo.Caption := '再想想';
    BtnNo.Left := 232; BtnNo.Top := 250; BtnNo.Width := 110; BtnNo.Height := 36;
    BtnNo.Default := True;
    BtnNo.ModalResult := mrNo;
    BtnYes := TButton.Create(F);
    BtnYes.Parent := F;
    BtnYes.Caption := '忍痛卸载';
    BtnYes.Left := 356; BtnYes.Top := 250; BtnYes.Width := 110; BtnYes.Height := 36;
    BtnYes.ModalResult := mrYes;
    if F.ShowModal() = mrYes then Result := True;
  finally
    F.Free();
  end;
end;

// Before uninstalling, stop the tray app and the bundled node server so
// files are not locked. The tray exe stops its own node child (it matches
// only node.exe of THIS install); taskkill is a hard-kill fallback.
procedure KillAppProcesses();
var
  ErrCode: Integer;
begin
  Exec(ExpandConstant('{app}\DshMini.exe'), '--stop', '', SW_HIDE, ewWaitUntilTerminated, ErrCode);
  Exec('taskkill.exe', '/F /IM DshMini.exe', '', SW_HIDE, ewWaitUntilTerminated, ErrCode);
end;

// Best-effort cleanup command (rmdir never raises and never follows
// junctions). The running uninstaller itself is retried every second
// until it succeeds (the exe stays locked while the uninstaller runs,
// so we poll up to ~30s until the user closed the done dialog).
function BuildCleanupCmdLine(AppDir: String): String;
var
  Unins: String;
begin
  Unins := ExpandConstant('{uninstallexe}');
  Result := '/c rmdir /s /q "' + AppDir + '\app" & ' +
    'rmdir /s /q "' + AppDir + '\home" & ' +
    'rmdir /s /q "' + AppDir + '\node" & ' +
    'rmdir /s /q "' + AppDir + '\.temp" & ' +
    'rmdir /s /q "' + AppDir + '\.npm-cache" & ' +
    'rmdir /s /q "' + AppDir + '\backups" & ' +
    'del /f /q "' + AppDir + '\DshMini.exe" & ' +
    'del /f /q "' + AppDir + '\LICENSE.txt" & ' +
    'del /f /q "' + AppDir + '\whale-desktop.ico" & ' +
    'del /f /q "' + AppDir + '\uninstall.ico" & ' +
    'del /f /q "' + AppDir + '\.tray.log" & ' +
    'for /l %i in (1,1,300) do @(del /f /q "' + Unins + '" >nul 2>&1 & ' +
    'if not exist "' + Unins + '" (del /f /q "' + AppDir + '\unins000.dat" >nul 2>&1 & del /f /q "' + AppDir + '\cry.bmp" >nul 2>&1 & del /f /q "' + AppDir + '\bye.bmp" >nul 2>&1 & rmdir /s /q "' + AppDir + '" >nul 2>&1 & exit) & ' +
    'ping -n 1 127.0.0.1 >nul)';
end;

// One-window uninstall progress: bar + status line. When done, the window
// closes and the caller shows the farewell dialog. (No modal-switching
// tricks - two plain windows is the stable pattern.)
procedure ShowUninstallProgress(AppDir: String);
var
  F: TForm;
  Bar: TNewProgressBar;
  Lbl: TLabel;
  i: Integer;
  ErrCode: Integer;
begin
  F := TForm.Create(nil);
  F.Caption := '正在卸载 DeepSeek Harness Mini';
  F.ClientWidth := 560;
  F.ClientHeight := 140;
  F.Position := poScreenCenter;
  F.BorderStyle := bsDialog;

  Lbl := TLabel.Create(F);
  Lbl.Parent := F;
  Lbl.AutoSize := False;
  Lbl.Left := 16; Lbl.Top := 16; Lbl.Width := 528; Lbl.Height := 24;
  Lbl.Caption := '正在停止服务...';

  Bar := TNewProgressBar.Create(F);
  Bar.Parent := F;
  Bar.Left := 16; Bar.Top := 56; Bar.Width := 528; Bar.Height := 24;
  Bar.Min := 0; Bar.Max := 100; Bar.Position := 0;

  F.Show();
  F.Refresh();

  // 1) stop services
  KillAppProcesses();
  Sleep(700);
  Bar.Position := 15;
  Lbl.Caption := '正在删除快捷方式...';
  F.Refresh();

  // 2) shortcuts
  DeleteFile(ExpandConstant('{autodesktop}\{#MyAppName}.lnk'));
  DelTree(ExpandConstant('{group}'), True, True, True);
  Sleep(400);
  Bar.Position := 30;
  Lbl.Caption := '正在清理注册表...';
  F.Refresh();

  // 3) registry
  RegDeleteKeyIncludingSubkeys(HKEY_CURRENT_USER,
    'Software\Microsoft\Windows\CurrentVersion\Uninstall\{B7E4F6A2-9C31-4D7E-8A0F-2D5E9C1B4A60}_is1');
  Sleep(400);
  Bar.Position := 50;
  Lbl.Caption := '正在删除程序文件...';
  F.Refresh();

  // 4) files (async: the uninstaller itself is deleted after it exits)
  Exec(ExpandConstant('{cmd}'), BuildCleanupCmdLine(AppDir), '', SW_HIDE, ewNoWait, ErrCode);

  for i := 0 to 10 do
  begin
    Sleep(250);
    Bar.Position := 50 + i * 5;
    F.Refresh();
  end;

  F.Free();
end;

// Farewell dialog (modal, standard): read the art from {app}; the cleanup
// cmd waits for the uninstaller to exit before deleting it, so the file
// is still there.
procedure ShowByeDialog();
var
  F: TForm;
  Btn: TButton;
begin
  F := TForm.Create(nil);
  try
    F.Caption := '卸载完成';
    F.ClientWidth := 560;
    F.ClientHeight := 320;
    F.Position := poScreenCenter;
    F.BorderStyle := bsDialog;
    DecorateDialog(F, 'bye.bmp', '卸载完成啦...' + #13#10 +
      '鲸鱼娘打包好了行李,这就离开。' + #13#10 +
      '期待再次相见,随时欢迎你回来~');
    Btn := TButton.Create(F);
    Btn.Parent := F;
    Btn.Caption := '后会有期';
    Btn.Left := 356; Btn.Top := 250; Btn.Width := 110; Btn.Height := 36;
    Btn.Default := True;
    Btn.ModalResult := mrOk;
    F.ShowModal();
  finally
    F.Free();
  end;
end;

function InitializeUninstall(): Boolean;
var
  AppDir: String;
  ErrCode: Integer;
begin
  // Take over the whole uninstall flow: our own tearful confirm, a
  // one-window progress bar with status line, done state in the same
  // window. Returning False always: the stock Inno dialogs never appear.
  Result := False;
  AppDir := ExpandConstant('{app}');

  if UninstallSilent() then
  begin
    KillAppProcesses();
    Sleep(800);
    DeleteFile(ExpandConstant('{autodesktop}\{#MyAppName}.lnk'));
    DelTree(ExpandConstant('{group}'), True, True, True);
    RegDeleteKeyIncludingSubkeys(HKEY_CURRENT_USER,
      'Software\Microsoft\Windows\CurrentVersion\Uninstall\{B7E4F6A2-9C31-4D7E-8A0F-2D5E9C1B4A60}_is1');
    Exec(ExpandConstant('{cmd}'), BuildCleanupCmdLine(AppDir), '', SW_HIDE, ewNoWait, ErrCode);
  end
  else
  begin
    if not ShowUninstallConfirm() then Exit;
    ShowUninstallProgress(AppDir);
    ShowByeDialog();
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  // Uninstall flow is fully taken over in InitializeUninstall; nothing to do.
end;
