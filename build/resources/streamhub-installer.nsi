Unicode true
!include "MUI2.nsh"

Name "StreamHub"
Icon "build\\resources\\icons\\icon-16-32-48-256.ico"
UninstallIcon "build\\resources\\icons\\icon-16-32-48-256.ico"
OutFile "StreamHub-Windows-x64-Setup.exe"
InstallDir "$LOCALAPPDATA\\Programs\\StreamHub"
RequestExecutionLevel user
SetCompressor /SOLID lzma

!define MUI_ABORTWARNING
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Section "Install"
  SetOutPath "$INSTDIR"
  File /r "${APP_SOURCE}\\*"
  WriteUninstaller "$INSTDIR\\Uninstall.exe"
  CreateDirectory "$SMPROGRAMS\\StreamHub"
  CreateShortcut "$SMPROGRAMS\\StreamHub\\StreamHub.lnk" "$INSTDIR\\streamlink-twitch-gui.exe" "" "$INSTDIR\\streamlink-twitch-gui.exe" 0
  CreateShortcut "$DESKTOP\\StreamHub.lnk" "$INSTDIR\\streamlink-twitch-gui.exe" "" "$INSTDIR\\streamlink-twitch-gui.exe" 0
  CreateShortcut "$SMPROGRAMS\\StreamHub\\Uninstall.lnk" "$INSTDIR\\Uninstall.exe"
  WriteRegStr HKCU "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\StreamHub" "DisplayName" "StreamHub"
  WriteRegStr HKCU "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\StreamHub" "DisplayIcon" "$INSTDIR\\streamlink-twitch-gui.exe,0"
  WriteRegStr HKCU "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\StreamHub" "Publisher" "StreamHub"
  WriteRegStr HKCU "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\StreamHub" "UninstallString" '"$INSTDIR\\Uninstall.exe"'
  WriteRegStr HKCU "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\StreamHub" "InstallLocation" "$INSTDIR"
SectionEnd

Section "Uninstall"
  Delete "$DESKTOP\\StreamHub.lnk"
  Delete "$SMPROGRAMS\\StreamHub\\StreamHub.lnk"
  Delete "$SMPROGRAMS\\StreamHub\\Uninstall.lnk"
  RMDir "$SMPROGRAMS\\StreamHub"
  RMDir /r "$INSTDIR"
  DeleteRegKey HKCU "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\StreamHub"
SectionEnd
