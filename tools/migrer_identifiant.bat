@echo off
rem ======================================================================
rem  Recharge237 - Passage a la nouvelle identite de ServeurApp (29/10/2026)
rem
rem  Ancien identifiant : com.example.projettest
rem  Nouvel identifiant : com.recharge237.serveur
rem
rem  A lancer APRES avoir installe la nouvelle version (Run dans IntelliJ)
rem  sur chaque telephone branche. Pour chaque telephone, ce script :
rem   1. verifie que la NOUVELLE version est bien installee ;
rem   2. lui accorde la reactivation automatique de l'accessibilite ;
rem   3. desinstalle l'ANCIENNE version (apres ta confirmation), sinon elle
rem      continuerait a prendre des commandes en parallele.
rem  Si la nouvelle version n'est pas installee, l'ancienne n'est PAS touchee.
rem ======================================================================
chcp 65001 >nul
setlocal enabledelayedexpansion
set NOUVEAU=com.recharge237.serveur
set ANCIEN=com.example.projettest
set ADB=adb
where adb >nul 2>&1
if errorlevel 1 set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe

set N=0
for /f "skip=1 tokens=1,2" %%a in ('"%ADB%" devices') do (
  if "%%b"=="device" (
    set /a N+=1
    call :migrer %%a
  )
)
if "!N!"=="0" echo AUCUN TELEPHONE CONNECTE.
echo.
pause
exit /b 0

:migrer
set DEV=%~1
echo.
echo ===== Telephone !DEV! =====
"%ADB%" -s "!DEV!" shell pm list packages %NOUVEAU% | findstr /c:"package:%NOUVEAU%" >nul
if errorlevel 1 (
  echo Nouvelle version NON installee : lance d'abord ServeurApp depuis IntelliJ.
  echo L'ancienne version est laissee en place.
  exit /b 0
)
echo [OK] Nouvelle version installee.
"%ADB%" -s "!DEV!" shell pm grant %NOUVEAU% android.permission.WRITE_SECURE_SETTINGS
echo [OK] Reactivation automatique de l'accessibilite accordee.
"%ADB%" -s "!DEV!" shell pm list packages %ANCIEN% | findstr /c:"package:%ANCIEN%" >nul
if errorlevel 1 (
  echo Ancienne version deja absente.
  exit /b 0
)
choice /c ON /m "Desinstaller l'ancienne version de ServeurApp sur !DEV! (O = oui, N = non)"
if errorlevel 2 (
  echo Ancienne version conservee.
  exit /b 0
)
"%ADB%" -s "!DEV!" uninstall %ANCIEN%
echo [OK] Ancienne version desinstallee.
exit /b 0
