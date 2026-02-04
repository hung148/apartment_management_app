;--------------------------------
; Apartment Management - NSIS Installer
; Vietnamese Version
;--------------------------------

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "x64.nsh"
!include "FileFunc.nsh"

;--------------------------------
; General Settings
;--------------------------------
Name "Apartment Management"
OutFile "installer_output\ApartmentManagement-Setup-Vietnamese-1.0.2+7.exe"
InstallDir "$PROGRAMFILES64\ApartmentManagement"
InstallDirRegKey HKLM "Software\ApartmentManagement" "Install_Dir"
RequestExecutionLevel admin
ShowInstDetails show
ShowUninstDetails show
Unicode true
SetCompressor /SOLID lzma

;--------------------------------
; Defines
;--------------------------------
!define VCREDIST "vc_redist.x64.exe"
!define APP_EXE "apartment_management_project_2.exe"
!define APP_NAME "Apartment Management"
!define APP_VERSION "1.0.2+7"
!define PUBLISHER "Trinh Dinh Nguyen Hung"
!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\ApartmentManagement"
!define REG_KEY "Software\ApartmentManagement"

;--------------------------------
; Variables
;--------------------------------
Var VCRedistNeeded

;--------------------------------
; Modern UI Settings
;--------------------------------
!define MUI_ABORTWARNING
!define MUI_ICON "${NSISDIR}\Contrib\Graphics\Icons\modern-install.ico"
!define MUI_UNICON "${NSISDIR}\Contrib\Graphics\Icons\modern-uninstall.ico"
!define MUI_WELCOMEFINISHPAGE_BITMAP "${NSISDIR}\Contrib\Graphics\Wizard\win.bmp"
!define MUI_UNWELCOMEFINISHPAGE_BITMAP "${NSISDIR}\Contrib\Graphics\Wizard\win.bmp"

;--------------------------------
; Pages
;--------------------------------
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES

!define MUI_FINISHPAGE_RUN "$INSTDIR\${APP_EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "Khởi chạy ${APP_NAME}"
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH

;--------------------------------
; Language - Vietnamese Only
;--------------------------------
!insertmacro MUI_LANGUAGE "Vietnamese"

;--------------------------------
; Version Information
;--------------------------------
VIProductVersion "1.0.0.0"
VIAddVersionKey "ProductName" "${APP_NAME}"
VIAddVersionKey "CompanyName" "${PUBLISHER}"
VIAddVersionKey "FileDescription" "${APP_NAME} Installer"
VIAddVersionKey "FileVersion" "${APP_VERSION}"
VIAddVersionKey "ProductVersion" "${APP_VERSION}"
VIAddVersionKey "LegalCopyright" "Copyright © 2026 ${PUBLISHER}"

;--------------------------------
; Installer Section
;--------------------------------
Section "Install" SecInstall

  SectionIn RO  ; Read-only section (cannot be deselected)
  
  ; Set output path to installation directory
  SetOutPath "$INSTDIR"
  
  ; Copy all release files recursively
  File /r "build\windows\x64\runner\Release\*.*"
  
  ; Create desktop shortcut
  CreateShortcut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}" \
    "" "$INSTDIR\${APP_EXE}" 0 SW_SHOWNORMAL \
    "" "Khởi chạy ${APP_NAME}"
  
  ; Create Start Menu shortcuts
  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
  CreateShortcut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}" \
    "" "$INSTDIR\${APP_EXE}" 0 SW_SHOWNORMAL \
    "" "Khởi chạy ${APP_NAME}"
  CreateShortcut "$SMPROGRAMS\${APP_NAME}\Gỡ cài đặt.lnk" "$INSTDIR\Uninstall.exe" \
    "" "$INSTDIR\Uninstall.exe" 0 SW_SHOWNORMAL \
    "" "Gỡ cài đặt ${APP_NAME}"
  
  ; Write uninstaller
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  
  ; Write installation directory to registry
  WriteRegStr HKLM "${REG_KEY}" "Install_Dir" "$INSTDIR"
  WriteRegStr HKLM "${REG_KEY}" "Version" "${APP_VERSION}"
  
  ; Write uninstall information to registry
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKLM "${UNINST_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKLM "${UNINST_KEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayIcon" "$INSTDIR\${APP_EXE},0"
  WriteRegStr HKLM "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${UNINST_KEY}" "Publisher" "${PUBLISHER}"
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayVersion" "${APP_VERSION}"
  WriteRegDWORD HKLM "${UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINST_KEY}" "NoRepair" 1
  
  ; Estimate install size (in KB)
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  IntFmt $0 "0x%08X" $0
  WriteRegDWORD HKLM "${UNINST_KEY}" "EstimatedSize" "$0"
  
  ; Install VC++ Redistributable if needed
  ${If} $VCRedistNeeded == 1
    DetailPrint "Đang cài đặt Visual C++ Runtime..."
    Call InstallVCRedist
  ${Else}
    DetailPrint "Visual C++ Runtime đã được cài đặt"
  ${EndIf}
  
SectionEnd

;--------------------------------
; Uninstaller Section
;--------------------------------
Section "Uninstall"

  ; Remove shortcuts
  Delete "$DESKTOP\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\Gỡ cài đặt.lnk"
  RMDir "$SMPROGRAMS\${APP_NAME}"
  
  ; Remove installed files and directories
  RMDir /r "$INSTDIR"
  
  ; Remove registry keys
  DeleteRegKey HKLM "${REG_KEY}"
  DeleteRegKey HKLM "${UNINST_KEY}"
  
  ; Show completion message
  ${IfNot} ${Silent}
    MessageBox MB_OK "${APP_NAME} đã được gỡ khỏi máy tính của bạn thành công."
  ${EndIf}

SectionEnd

;--------------------------------
; Functions
;--------------------------------

; Called when installer starts
Function .onInit

  ; Check if 64-bit Windows
  ${IfNot} ${RunningX64}
    MessageBox MB_OK|MB_ICONSTOP "Ứng dụng này yêu cầu Windows 64-bit. Không thể tiếp tục cài đặt."
    Abort
  ${EndIf}
  
  ; Check if already installed
  ReadRegStr $0 HKLM "${REG_KEY}" "Install_Dir"
  ${If} $0 != ""
    MessageBox MB_YESNO|MB_ICONQUESTION "${APP_NAME} đã được cài đặt tại:$\n$\n$0$\n$\nBạn có muốn gỡ phiên bản cũ không?" IDNO done

    ; User clicked Yes - manually uninstall
    DetailPrint "Đang gỡ phiên bản cũ..."
    
    ; Remove shortcuts
    Delete "$DESKTOP\${APP_NAME}.lnk"
    Delete "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk"
    Delete "$SMPROGRAMS\${APP_NAME}\Gỡ cài đặt.lnk"
    RMDir "$SMPROGRAMS\${APP_NAME}"
    
    ; Remove installed files and directories
    RMDir /r "$0"
    
    ; Remove registry keys
    DeleteRegKey HKLM "${REG_KEY}"
    DeleteRegKey HKLM "${UNINST_KEY}"
      
    done:
  ${EndIf}
  
  ; Initialize variables
  StrCpy $VCRedistNeeded "0"
  
  ; Check for VC++ Redistributable
  Call CheckVCRedist
  
FunctionEnd

; Check if VC++ 2015-2022 Redistributable x64 is installed
Function CheckVCRedist
  
  Push $0
  Push $1
  
  ClearErrors
  
  ; Check 64-bit registry location first
  ReadRegStr $0 HKLM "SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" "Version"
  ${If} ${Errors}
    ; Try WOW6432Node (for 32-bit installer on 64-bit Windows)
    ClearErrors
    ReadRegStr $0 HKLM "SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" "Version"
    ${If} ${Errors}
      ; Not found - need to install
      StrCpy $VCRedistNeeded "1"
      DetailPrint "Không tìm thấy Visual C++ Runtime - sẽ cài đặt"
    ${Else}
      DetailPrint "Đã tìm thấy Visual C++ Runtime: $0"
      StrCpy $VCRedistNeeded "0"
    ${EndIf}
  ${Else}
    DetailPrint "Đã tìm thấy Visual C++ Runtime: $0"
    StrCpy $VCRedistNeeded "0"
  ${EndIf}
  
  Pop $1
  Pop $0
  
FunctionEnd

; Install Visual C++ Redistributable
Function InstallVCRedist
  
  Push $0
  
  ; Check if VC++ redistributable file exists
  IfFileExists "$EXEDIR\${VCREDIST}" +3
    DetailPrint "LỖI: Không tìm thấy ${VCREDIST} trong thư mục cài đặt"
    Goto vcredist_end
  
  ; Extract to temp directory
  SetOutPath "$TEMP"
  File "${VCREDIST}"
  
  ; Run silent installation
  DetailPrint "Đang cài đặt Visual C++ Runtime (có thể mất một phút)..."
  ExecWait '"$TEMP\${VCREDIST}" /install /quiet /norestart' $0
  
  ; Check return code
  ${If} $0 == 0
    DetailPrint "Cài đặt Visual C++ Runtime thành công"
  ${ElseIf} $0 == 3010
    DetailPrint "Cài đặt Visual C++ Runtime thành công (nên khởi động lại)"
  ${Else}
    DetailPrint "Cài đặt Visual C++ Runtime trả về mã: $0"
  ${EndIf}
  
  ; Clean up
  Delete "$TEMP\${VCREDIST}"
  
  vcredist_end:
  Pop $0
  
FunctionEnd

; Called when uninstaller starts
Function un.onInit
  
  ; Check if running in silent mode
  ${If} ${Silent}
    ; Silent mode - skip confirmation
    Return
  ${EndIf}
  
  MessageBox MB_YESNO|MB_ICONQUESTION "Bạn có chắc chắn muốn gỡ bỏ hoàn toàn ${APP_NAME} và tất cả thành phần không?" IDYES +2
  Abort
FunctionEnd
