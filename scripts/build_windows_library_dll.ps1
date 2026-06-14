#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Build a Windows native library DLL/lib and optionally pack a NuGet package.

.DESCRIPTION
  Windows counterpart of scripts/build_xcode26_library_xcframework.sh. Builds one
  or more module DLLs via MSBuild, copies them with distributable names under
  dist/<version>/windows/, and (with -Package) produces the NativeToolkit NuGet
  package from scripts/nuget/NativeToolkit.

.PARAMETER Module
  Module to build (repeatable). Valid: WindowsLibrary, UnityWindowsPlugin.
  Default: WindowsLibrary.

.PARAMETER Configuration
  debug or release (default: release).

.PARAMETER Platform
  MSBuild platform (default: x64).

.PARAMETER LibraryVersion
  Library version used for default output naming and the NuGet package version.

.PARAMETER Output
  Output DLL path. Only allowed for a single module. The .lib is written next to it.

.PARAMETER Package
  Also pack the NuGet package (.nupkg). Only valid for packable modules (WindowsLibrary).
  The .nupkg is written next to the distributable DLL with the same base name
  (e.g. dist\<v>\windows\windows-native-toolkit-<v>.nupkg, or alongside -Output).

.PARAMETER Nuget
  Path to nuget.exe. If omitted, 'nuget' is resolved from PATH.

.EXAMPLE
  ./scripts/build_windows_library_dll.ps1 -Configuration release -LibraryVersion 1.3.0

.EXAMPLE
  ./scripts/build_windows_library_dll.ps1 -c debug -v 1.3.0 -o C:\tmp\windows-native-toolkit-verify.dll

.EXAMPLE
  ./scripts/build_windows_library_dll.ps1 -m WindowsLibrary -v 1.3.0 -Package

.EXAMPLE
  ./scripts/build_windows_library_dll.ps1 -c release -m WindowsLibrary -v 1.1.0 -o dist\1.4.0\windows\windows-native-toolkit-1.1.0.dll -Package
#>
[CmdletBinding()]
param(
    [Alias('m')][string[]]$Module = @('WindowsLibrary'),
    [Alias('c')][string]$Configuration = 'release',
    [Alias('p')][string]$Platform = 'x64',
    [Alias('v')][string]$LibraryVersion = '',
    [Alias('o')][string]$Output = '',
    [switch]$Package,
    [string]$Nuget = '',
    [Alias('h')][switch]$Help
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Step([string]$prefix, [string]$message) {
    Write-Host "[$prefix] $message"
}

function Fail([string]$message) {
    Write-Error $message
    exit 1
}

# Rewrite the VERSIONINFO literals in a Win32 .rc and persist the change, so the
# released version is stamped into source (parity with the macOS pbxproj update).
# The .rc is UTF-16LE; its encoding is preserved.
function Update-RcVersion([string]$rcPath, [string]$version) {
    if (-not (Test-Path $rcPath)) { return }
    $verParts = @($version -split '\.')
    while ($verParts.Count -lt 4) { $verParts += '0' }
    $verComma = ($verParts[0..3] -join ',')

    $enc = [System.Text.Encoding]::Unicode
    $text = [System.IO.File]::ReadAllText($rcPath, $enc)
    $text = [regex]::Replace($text, 'FILEVERSION\s+\d+,\d+,\d+,\d+', "FILEVERSION $verComma")
    $text = [regex]::Replace($text, 'PRODUCTVERSION\s+\d+,\d+,\d+,\d+', "PRODUCTVERSION $verComma")
    $text = [regex]::Replace($text, '"FileVersion",\s*"[0-9][0-9.]*"', "`"FileVersion`", `"$version`"")
    $text = [regex]::Replace($text, '"ProductVersion",\s*"[0-9][0-9.]*"', "`"ProductVersion`", `"$version`"")
    [System.IO.File]::WriteAllText($rcPath, $text, $enc)
    Write-Step 'info' "Stamped $([System.IO.Path]::GetFileName($rcPath)) version $version (FILEVERSION $verComma)"
}

function Show-Usage {
    Write-Host @'
Usage: ./scripts/build_windows_library_dll.ps1 [-Module <name>]... [-Configuration <debug|release>] [-Platform <x64>] [-LibraryVersion <version>] [-Output <path>] [-Package] [-Nuget <path>]
  -m, -Module          Module to build (repeatable): WindowsLibrary, UnityWindowsPlugin (default: WindowsLibrary)
  -c, -Configuration   debug or release (default: release)
  -p, -Platform        MSBuild platform (default: x64)
  -v, -LibraryVersion  library version for default output naming / NuGet version
  -o, -Output          output DLL path (single module only; .lib written alongside)
      -Package         also pack the NuGet package (.nupkg) for packable modules
      -Nuget           path to nuget.exe (default: resolved from PATH)
  -h, -Help            show help
'@
}

if ($Help) { Show-Usage; exit 0 }

# ---------------------------------------------------------------------------
# Paths and module configuration
# ---------------------------------------------------------------------------

$RepoRoot = Split-Path -Parent $PSScriptRoot

# Per-module build configuration.
$ModuleConfig = @{
    'WindowsLibrary' = @{
        Project  = 'windows\WindowsLibrary\WindowsLibrary.vcxproj'
        Def      = 'windows\WindowsLibrary\WindowsLibrary.def'
        Rc       = 'windows\WindowsLibrary\WindowsLibrary.rc'
        DllName  = 'NativeToolkit'
        Prefix   = 'windows-native-toolkit'
        Packable = $true
        # Public headers shipped in the NuGet package (internal headers excluded).
        Headers  = @(
            'windows\WindowsLibrary\common.h',
            'windows\WindowsLibrary\WindowsDialogManager.h',
            'windows\WindowsLibrary\WindowsNotificationManager.h'
        )
    }
    'UnityWindowsPlugin' = @{
        Project  = 'windows\UnityWindowsPlugin\UnityWindowsPlugin.vcxproj'
        Def      = 'windows\UnityWindowsPlugin\UnityWindowsPlugin.def'
        Rc       = 'windows\UnityWindowsPlugin\UnityWindowsPlugin.rc'
        DllName  = 'UnityWindowsPlugin'
        Prefix   = 'unity-windows-native-toolkit'
        Packable = $false
        Headers  = @()
    }
}

# ---------------------------------------------------------------------------
# Validate options (parity with the macOS script)
# ---------------------------------------------------------------------------

$Configuration = $Configuration.ToLowerInvariant()
if ($Configuration -ne 'debug' -and $Configuration -ne 'release') {
    Fail "Configuration must be 'debug' or 'release'."
}

if (-not $Module -or $Module.Count -eq 0) { $Module = @('WindowsLibrary') }

foreach ($m in $Module) {
    if (-not $ModuleConfig.ContainsKey($m)) {
        Fail "Unknown module '$m'. Valid modules: $($ModuleConfig.Keys -join ', ')"
    }
}

$OutputSet = -not [string]::IsNullOrEmpty($Output)

if ($OutputSet -and $Module.Count -gt 1) {
    Show-Usage
    Fail "-Output is not allowed for multi-module builds."
}

if (-not [string]::IsNullOrEmpty($LibraryVersion)) {
    if ($LibraryVersion -match '[\s/]') {
        Show-Usage
        Fail "-LibraryVersion must not contain spaces or '/' characters."
    }
}

if (-not $OutputSet -and [string]::IsNullOrEmpty($LibraryVersion)) {
    Show-Usage
    Fail "-LibraryVersion is required when -Output is not specified."
}

if ($Package -and [string]::IsNullOrEmpty($LibraryVersion)) {
    Fail "-LibraryVersion is required with -Package (used as the NuGet package version)."
}

# MSBuild configuration name (Debug/Release).
$MsbuildConfig = if ($Configuration -eq 'debug') { 'Debug' } else { 'Release' }

# ---------------------------------------------------------------------------
# Resolve toolchain
# ---------------------------------------------------------------------------

function Resolve-MSBuild {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) {
        Fail "vswhere not found. Install Visual Studio (Build Tools or Community)."
    }
    $msbuild = & $vswhere -latest -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe' | Select-Object -First 1
    if ([string]::IsNullOrEmpty($msbuild) -or -not (Test-Path $msbuild)) {
        Fail "MSBuild not found via vswhere."
    }
    return $msbuild
}

function Resolve-Nuget {
    if (-not [string]::IsNullOrEmpty($Nuget)) {
        if (-not (Test-Path $Nuget)) { Fail "nuget.exe not found at: $Nuget" }
        return $Nuget
    }
    $cmd = Get-Command nuget -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $bundled = Join-Path $PSScriptRoot 'nuget\nuget.exe'
    if (Test-Path $bundled) { return $bundled }
    Fail "nuget.exe not found. Place it at scripts/nuget/nuget.exe, add it to PATH, or pass -Nuget <path>. Download: https://www.nuget.org/downloads"
}

$MSBuild = Resolve-MSBuild

# ---------------------------------------------------------------------------
# Build a single module -> produces <DllName>.dll/.lib in $stageDir
# ---------------------------------------------------------------------------

function Build-Module([hashtable]$cfg, [string]$stageDir) {
    $projectPath = Join-Path $RepoRoot $cfg.Project
    $defPath     = Join-Path $RepoRoot $cfg.Def
    $dllName     = $cfg.DllName

    if (-not (Test-Path $projectPath)) { Fail "Project not found: $projectPath" }
    if (-not (Test-Path $defPath))     { Fail "DEF file not found: $defPath" }

    # Stage a temporary DEF with the distributable LIBRARY name so the DLL/lib
    # are emitted as <DllName>.dll / <DllName>.lib.
    $tempDef = Join-Path ([System.IO.Path]::GetTempPath()) "$dllName.def"
    $defLines = Get-Content -LiteralPath $defPath
    $defLines = $defLines | ForEach-Object {
        if ($_ -match '^\s*LIBRARY') { "LIBRARY $dllName" } else { $_ }
    }
    Set-Content -LiteralPath $tempDef -Value $defLines -Encoding ASCII

    # Stamp the source version resource (FILEVERSION / PRODUCTVERSION) from the
    # library version and persist it, mirroring the macOS pbxproj version update.
    if (-not [string]::IsNullOrEmpty($LibraryVersion) -and -not [string]::IsNullOrEmpty($cfg.Rc)) {
        Update-RcVersion (Join-Path $RepoRoot $cfg.Rc) $LibraryVersion
    }

    # Override props: disable type-library registration and inject the temp DEF.
    $tempProps = Join-Path ([System.IO.Path]::GetTempPath()) "$dllName.override.props"
    $propsContent = @"
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
    <NativeToolkitTempDef>$tempDef</NativeToolkitTempDef>
  </PropertyGroup>
  <ItemDefinitionGroup>
    <Link>
      <RegisterOutput>false</RegisterOutput>
      <ModuleDefinitionFile>`$(NativeToolkitTempDef)</ModuleDefinitionFile>
    </Link>
  </ItemDefinitionGroup>
</Project>
"@
    Set-Content -LiteralPath $tempProps -Value $propsContent -Encoding UTF8

    if (Test-Path $stageDir) { Remove-Item -Recurse -Force $stageDir }
    New-Item -ItemType Directory -Force -Path $stageDir | Out-Null
    $outDir = (Resolve-Path $stageDir).Path
    if (-not $outDir.EndsWith('\')) { $outDir = "$outDir\" }

    Write-Step 'build' "MSBuild $($cfg.DllName) ($MsbuildConfig|$Platform)"
    & $MSBuild $projectPath /t:Build /p:Configuration=$MsbuildConfig /p:Platform=$Platform `
        /p:TargetName=$dllName /p:OutDir=$outDir /p:ForceImportBeforeCppTargets=$tempProps `
        /nologo /v:minimal | Out-Host
    $buildExit = $LASTEXITCODE

    Remove-Item -LiteralPath $tempDef -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tempProps -Force -ErrorAction SilentlyContinue

    if ($buildExit -ne 0) { Fail "[$($cfg.DllName)] Build failed (exit $buildExit)." }

    $dll = Join-Path $outDir "$dllName.dll"
    $lib = Join-Path $outDir "$dllName.lib"
    if (-not (Test-Path $dll)) { Fail "[$($cfg.DllName)] Output not found: $dll" }
    if (-not (Test-Path $lib)) { Fail "[$($cfg.DllName)] Output not found: $lib" }

    # Drop intermediate link artifacts.
    Remove-Item -Path (Join-Path $outDir "$dllName.exp") -Force -ErrorAction SilentlyContinue

    return [pscustomobject]@{ Dll = $dll; Lib = $lib }
}

# ---------------------------------------------------------------------------
# Pack the NuGet package from scripts/nuget/NativeToolkit
# ---------------------------------------------------------------------------

function Invoke-NugetPack([hashtable]$cfg, [pscustomobject]$built, [string]$nupkgTarget) {
    $nuget = Resolve-Nuget
    $templateDir = Join-Path $PSScriptRoot 'nuget\NativeToolkit'
    if (-not (Test-Path $templateDir)) { Fail "NuGet template not found: $templateDir" }

    # Stage a packing layout next to a copy of the template.
    $packDir = Join-Path ([System.IO.Path]::GetTempPath()) "nupkg-$($cfg.DllName)-$LibraryVersion"
    if (Test-Path $packDir) { Remove-Item -Recurse -Force $packDir }
    New-Item -ItemType Directory -Force -Path $packDir | Out-Null

    Copy-Item -Recurse -Force (Join-Path $templateDir '*') $packDir

    # Stage binaries (x64 runtime path).
    $nativeDir = Join-Path $packDir 'runtimes\win-x64\native'
    New-Item -ItemType Directory -Force -Path $nativeDir | Out-Null
    Copy-Item -Force $built.Dll (Join-Path $nativeDir "$($cfg.DllName).dll")
    Copy-Item -Force $built.Lib (Join-Path $nativeDir "$($cfg.DllName).lib")

    # Stage public headers.
    $includeDir = Join-Path $packDir 'include'
    New-Item -ItemType Directory -Force -Path $includeDir | Out-Null
    foreach ($h in $cfg.Headers) {
        $src = Join-Path $RepoRoot $h
        if (-not (Test-Path $src)) { Fail "Public header not found: $src" }
        Copy-Item -Force $src $includeDir
    }

    # Pack to a temp dir (nuget names it NativeToolkit.<version>.nupkg), then move
    # the package to the requested target path/name (next to the distributable DLL).
    $packOut = Join-Path $packDir '_out'
    New-Item -ItemType Directory -Force -Path $packOut | Out-Null

    Write-Step 'package' "nuget pack NativeToolkit $LibraryVersion"
    $nuspec = Join-Path $packDir 'NativeToolkit.nuspec'
    & $nuget pack $nuspec -Version $LibraryVersion -OutputDirectory $packOut -NonInteractive -Verbosity quiet | Out-Host
    $packExit = $LASTEXITCODE
    if ($packExit -ne 0) { Remove-Item -Recurse -Force $packDir -ErrorAction SilentlyContinue; Fail "nuget pack failed (exit $packExit)." }

    $produced = Join-Path $packOut "NativeToolkit.$LibraryVersion.nupkg"
    if (-not (Test-Path $produced)) { Remove-Item -Recurse -Force $packDir -ErrorAction SilentlyContinue; Fail "Expected package not found: $produced" }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $nupkgTarget) | Out-Null
    Move-Item -Force $produced $nupkgTarget
    Remove-Item -Recurse -Force $packDir -ErrorAction SilentlyContinue

    return $nupkgTarget
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

foreach ($moduleName in $Module) {
    $cfg = $ModuleConfig[$moduleName]

    if ($Package -and -not $cfg.Packable) {
        Fail "[$moduleName] is not packable as NuGet. Remove -Package or choose WindowsLibrary."
    }

    Write-Step 'info' "[$moduleName] Building ($MsbuildConfig|$Platform) version=$(if ($LibraryVersion) { $LibraryVersion } else { 'n/a' })"

    $stageDir = Join-Path $RepoRoot "windows\Build\$moduleName"
    Write-Step 'clean' "[$moduleName] Cleaning build staging"
    $built = Build-Module $cfg $stageDir

    # Resolve the distributable DLL output path.
    if ($OutputSet) {
        $dllTarget = if ([System.IO.Path]::IsPathRooted($Output)) { $Output } else { Join-Path $RepoRoot $Output }
    } else {
        $suffix = if ($Configuration -eq 'debug') { "-debug" } else { "" }
        $fileName = "$($cfg.Prefix)-$LibraryVersion$suffix.dll"
        $dllTarget = Join-Path $RepoRoot "dist\$LibraryVersion\windows\$fileName"
    }
    $libTarget = [System.IO.Path]::ChangeExtension($dllTarget, '.lib')

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dllTarget) | Out-Null
    Copy-Item -Force $built.Dll $dllTarget
    Copy-Item -Force $built.Lib $libTarget
    Write-Step 'done' "[$moduleName] Created $dllTarget and $libTarget"

    if ($Package) {
        # Place the package next to the distributable DLL with the same base name.
        $nupkgTarget = [System.IO.Path]::ChangeExtension($dllTarget, '.nupkg')
        $nupkg = Invoke-NugetPack $cfg $built $nupkgTarget
        Write-Step 'done' "[$moduleName] Created $nupkg"
    }
}
