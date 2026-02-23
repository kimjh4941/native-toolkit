@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
set "REPO_ROOT=%SCRIPT_DIR%.."
set "PROJECT=%REPO_ROOT%\windows\WindowsLibrary\WindowsLibrary.vcxproj"
set "DEF_FILE=%REPO_ROOT%\windows\WindowsLibrary\WindowsLibrary.def"

if "%~1"=="" goto usage

if exist "%~1" (
  set "SRC_DLL=%~1"
  set "DEST_DIR=%~2"
  if "%DEST_DIR%"=="" goto usage
  goto copy_only
)

set "CONFIG=%~1"
set "PLATFORM=%~2"
set "DEST_DIR=%~3"

if "%CONFIG%"=="" goto usage
if "%PLATFORM%"=="" goto usage
if "%DEST_DIR%"=="" goto usage

if not exist "%PROJECT%" (
  echo [ERROR] Project not found: "%PROJECT%"
  exit /b 1
)

if not exist "%DEF_FILE%" (
  echo [ERROR] DEF file not found: "%DEF_FILE%"
  exit /b 1
)

for /f "usebackq delims=" %%i in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -property installationPath 2^>nul`) do set "VS_INSTALL=%%i"
if "%VS_INSTALL%"=="" (
  echo [ERROR] Visual Studio not found. Install VS Build Tools or VS Community.
  exit /b 1
)

set "MSBUILD=%VS_INSTALL%\MSBuild\Current\Bin\MSBuild.exe"
if not exist "%MSBUILD%" set "MSBUILD=%VS_INSTALL%\MSBuild\Current\Bin\amd64\MSBuild.exe"
if not exist "%MSBUILD%" (
  echo [ERROR] MSBuild not found under: "%VS_INSTALL%"
  exit /b 1
)

if not exist "%DEST_DIR%" mkdir "%DEST_DIR%" >nul 2>&1
if not exist "%DEST_DIR%" (
  echo [ERROR] Failed to create destination directory: "%DEST_DIR%"
  exit /b 1
)

set "DEST_DIR_NOSLASH=%DEST_DIR%"
if "%DEST_DIR_NOSLASH:~-1%"=="\" set "DEST_DIR_NOSLASH=%DEST_DIR_NOSLASH:~0,-1%"
if "%DEST_DIR_NOSLASH:~-1%"=="/" set "DEST_DIR_NOSLASH=%DEST_DIR_NOSLASH:~0,-1%"
set "OUT_DIR=%DEST_DIR_NOSLASH%\\"

set "TEMP_DEF=%TEMP%\NativeToolkit.def"
copy /y "%DEF_FILE%" "%TEMP_DEF%" >nul
if errorlevel 1 (
  echo [ERROR] Failed to create temporary DEF file.
  exit /b 1
)

powershell -NoProfile -Command "$c=Get-Content '%TEMP_DEF%'; $c= $c | ForEach-Object { if ($_ -match '^\s*LIBRARY') { 'LIBRARY NativeToolkit' } else { $_ } }; Set-Content -Value $c '%TEMP_DEF%'" >nul
if errorlevel 1 (
  echo [ERROR] Failed to update DEF file.
  del /q "%TEMP_DEF%" >nul 2>&1
  exit /b 1
)

set "TEMP_PROPS=%TEMP%\NativeToolkit.override.props"
(
  echo ^<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003"^>
  echo   ^<PropertyGroup^>
  echo     ^<NativeToolkitTempDef^>%TEMP_DEF%^</NativeToolkitTempDef^>
  echo   ^</PropertyGroup^>
  echo   ^<ItemDefinitionGroup^>
  echo     ^<Link^>
  echo       ^<RegisterOutput^>false^</RegisterOutput^>
  echo       ^<ModuleDefinitionFile^>$^(NativeToolkitTempDef^)^</ModuleDefinitionFile^>
  echo     ^</Link^>
  echo   ^</ItemDefinitionGroup^>
  echo ^</Project^>
) > "%TEMP_PROPS%"
if errorlevel 1 (
  echo [ERROR] Failed to create temporary props file.
  del /q "%TEMP_DEF%" >nul 2>&1
  exit /b 1
)

"%MSBUILD%" "%PROJECT%" /t:Build /p:Configuration=%CONFIG% /p:Platform=%PLATFORM% /p:TargetName=NativeToolkit /p:OutDir="%OUT_DIR%" /p:ForceImportBeforeCppTargets="%TEMP_PROPS%"
if errorlevel 1 (
  echo [ERROR] Build failed.
  del /q "%TEMP_DEF%" >nul 2>&1
  del /q "%TEMP_PROPS%" >nul 2>&1
  exit /b 1
)

if not exist "%DEST_DIR%\NativeToolkit.dll" (
  echo [ERROR] Output not found: "%DEST_DIR%\NativeToolkit.dll"
  del /q "%TEMP_DEF%" >nul 2>&1
  del /q "%TEMP_PROPS%" >nul 2>&1
  exit /b 1
)

if not exist "%DEST_DIR%\NativeToolkit.lib" (
  echo [ERROR] Output not found: "%DEST_DIR%\NativeToolkit.lib"
  del /q "%TEMP_DEF%" >nul 2>&1
  del /q "%TEMP_PROPS%" >nul 2>&1
  exit /b 1
)

if exist "%DEST_DIR%\NativeToolkit.exp" del /q "%DEST_DIR%\NativeToolkit.exp" >nul 2>&1
if exist "%DEST_DIR%\NativeToolkit.pdb" del /q "%DEST_DIR%\NativeToolkit.pdb" >nul 2>&1

del /q "%TEMP_DEF%" >nul 2>&1
del /q "%TEMP_PROPS%" >nul 2>&1
echo [OK] Built: "%DEST_DIR%\NativeToolkit.dll" and "%DEST_DIR%\NativeToolkit.lib"
exit /b 0

:copy_only
if not exist "%SRC_DLL%" (
  echo [ERROR] Source DLL not found: "%SRC_DLL%"
  exit /b 1
)

if not exist "%DEST_DIR%" (
  mkdir "%DEST_DIR%" >nul 2>&1
)

if not exist "%DEST_DIR%" (
  echo [ERROR] Failed to create destination directory: "%DEST_DIR%"
  exit /b 1
)

copy /y "%SRC_DLL%" "%DEST_DIR%\NativeToolkit.dll" >nul
if errorlevel 1 (
  echo [ERROR] Copy failed.
  exit /b 1
)

echo [OK] Created: "%DEST_DIR%\NativeToolkit.dll"
exit /b 0

:usage
echo Usage:
echo   %~nx0 Debug x64 "path\to\output\dir"
echo   %~nx0 Release x64 "path\to\output\dir"
echo   %~nx0 "path\to\WindowsLibrary.dll" "path\to\output\dir"
exit /b 2
