@echo off
rem ======================================================================
rem  Recharge237 - Preparation d'un telephone serveur (une fois par telephone)
rem
rem  A lancer apres la PREMIERE installation de ServeurApp sur un telephone
rem  (cable USB ou debogage sans fil actif). Ce script :
rem   1. accorde WRITE_SECURE_SETTINGS a l'app : elle pourra ensuite
rem      REACTIVER TOUTE SEULE son service d'accessibilite si le systeme
rem      (HyperOS/MIUI notamment) le coupe, et faire le cycle mode avion ;
rem   2. active le service d'accessibilite ServeurApp tout de suite,
rem      sans retirer les autres services deja actifs ;
rem   3. retire l'app de l'optimisation batterie (Doze).
rem  La permission reste acquise apres une mise a jour (install -r).
rem  Elle est perdue seulement si l'app est DESINSTALLEE.
rem ======================================================================
chcp 65001 >nul
setlocal enabledelayedexpansion
set PKG=com.recharge237.serveur
set SVC=%PKG%/com.kavina.ussd_launcher.UssdAccessibilityService
set ADB=adb
where adb >nul 2>&1
if errorlevel 1 (
  if exist "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" (
    set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
  ) else (
    echo ERREUR : adb introuvable. Installe les Android Platform Tools.
    pause
    exit /b 1
  )
)

set N=0
for /f "skip=1 tokens=1,2" %%a in ('"%ADB%" devices') do (
  if "%%b"=="device" (
    set /a N+=1
    call :preparer %%a
  )
)
if "!N!"=="0" (
  echo AUCUN TELEPHONE CONNECTE.
  echo Branche le cable USB ou active le debogage sans fil, puis accepte
  echo la fenetre "Autoriser le debogage USB" sur le telephone.
)
echo.
echo Sur Xiaomi/Redmi, verifie aussi a la main une fois sur CHAQUE telephone :
echo   Parametres ^> Applications ^> ServeurApp Recharge237 ^> Demarrage auto : ACTIVE
echo   et Economiseur de batterie : Aucune restriction.
echo.
pause
exit /b 0

:preparer
set DEV=%~1
echo.
echo ##################################################################
echo  Telephone : !DEV!
echo ##################################################################
"%ADB%" -s "!DEV!" shell pm list packages %PKG% | findstr /i /c:"%PKG%" >nul
if errorlevel 1 (
  echo ServeurApp n'est pas installee sur ce telephone : ignore.
  exit /b 0
)
echo.
echo === 1. Autorisation WRITE_SECURE_SETTINGS ===
"%ADB%" -s "!DEV!" shell pm grant %PKG% android.permission.WRITE_SECURE_SETTINGS

echo.
echo === 2. Activation du service d'accessibilite ===
set CUR=
for /f "delims=" %%v in ('"%ADB%" -s "!DEV!" shell settings get secure enabled_accessibility_services') do set CUR=%%v
if "!CUR!"=="null" set CUR=
echo !CUR! | findstr /i /c:"%SVC%" >nul
if errorlevel 1 (
  if "!CUR!"=="" (set NEW=%SVC%) else (set NEW=!CUR!:%SVC%)
  "%ADB%" -s "!DEV!" shell settings put secure enabled_accessibility_services "!NEW!"
)
"%ADB%" -s "!DEV!" shell settings put secure accessibility_enabled 1

echo.
echo === 3. Hors optimisation batterie ===
"%ADB%" -s "!DEV!" shell cmd deviceidle whitelist +%PKG%

echo.
echo === Verification ===
"%ADB%" -s "!DEV!" shell dumpsys package %PKG% | findstr /i /c:"WRITE_SECURE_SETTINGS: granted=true" >nul
if errorlevel 1 (echo [KO] WRITE_SECURE_SETTINGS non accordee) else (echo [OK] WRITE_SECURE_SETTINGS accordee)
"%ADB%" -s "!DEV!" shell settings get secure enabled_accessibility_services | findstr /i /c:"%SVC%" >nul
if errorlevel 1 (echo [KO] Accessibilite ServeurApp non active) else (echo [OK] Accessibilite ServeurApp active)
exit /b 0
