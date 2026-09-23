#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Build the Windows C++ API static library and the C ABI DLL, with their public
  headers and their NuGet packages.

.DESCRIPTION
  Windows counterpart of scripts/build_xcode26_library_xcframework.sh. Builds
  one or both modules via MSBuild and copies them with distributable names
  under dist/<release>/windows/:

    WindowsLibraryCore - the C++ API, a static library
      windows-native-toolkit-<version>.lib        the static library
      include/NativeToolkit/*.h                   the public headers
      windows-native-toolkit-<version>.nupkg      -Package: NativeToolkit

    WindowsLibraryCApi - the C ABI, a DLL
      windows-native-toolkit-capi-<version>.dll   the DLL (its own name is NativeToolkitC.dll)
      windows-native-toolkit-capi-<version>.lib   its import library, which loads NativeToolkitC.dll
      include/NativeToolkitC/*.h                  the public headers
      windows-native-toolkit-capi-<version>.nupkg -Package: NativeToolkit.CApi

  Both need the Windows App SDK. The DLL imports
  Microsoft.WindowsAppRuntime.Bootstrap.dll, which has to sit next to it; a
  consumer of the static library restores Microsoft.WindowsAppSDK itself, and
  both NuGet packages declare it as a dependency.

  The NuGet package of the static library carries the Release and the Debug
  library, so -Package builds both configurations for that module whatever
  -Configuration says.

  -LibraryVersion must be the version the module's headers declare
  (NATIVETOOLKIT_VERSION_* in NativeToolkit/BuildStamp.h, NTK_VERSION_* in
  NativeToolkitC/Common.h): a binary stamped with another would tell a caller
  that checks ntk_version() the wrong thing.

  -ReleaseVersion names the dist/<release>/ folder. That is the version of the
  repository's release, not of this library: dist/1.11.0/android holds
  android-native-toolkit-1.3.0.aar. It defaults to -LibraryVersion.

.PARAMETER Module
  Module to build (repeatable). Valid: WindowsLibraryCore, WindowsLibraryCApi.
  Default: both.

.PARAMETER Configuration
  debug or release (default: release).

.PARAMETER Platform
  MSBuild platform (default: x64).

.PARAMETER LibraryVersion
  Library version. Must match what the module's public headers declare.

.PARAMETER ReleaseVersion
  Version of the dist/<release>/ folder (default: -LibraryVersion).

.PARAMETER Output
  Output path (.dll for the C ABI, .lib for the C++ API). Only allowed for a
  single module. The import library, the headers and the package are written
  alongside it.

.PARAMETER Package
  Pack the module's NuGet package next to the distributable.

.PARAMETER Nuget
  Path to nuget.exe. If omitted, 'nuget' is resolved from PATH.

.EXAMPLE
  ./scripts/build_windows_library_dll.ps1 -Configuration release -LibraryVersion 2.0.0 -ReleaseVersion 1.12.0 -Package

.EXAMPLE
  ./scripts/build_windows_library_dll.ps1 -m WindowsLibraryCApi -c debug -v 2.0.0 -o C:\tmp\windows-native-toolkit-capi-verify.dll

.EXAMPLE
  ./scripts/build_windows_library_dll.ps1 -m WindowsLibraryCore -c release -v 2.0.0 -o dist\1.12.0\windows\windows-native-toolkit-2.0.0.lib
#>
[CmdletBinding()]
param(
    [Alias('m')][string[]]$Module = @('WindowsLibraryCore', 'WindowsLibraryCApi'),
    [Alias('c')][string]$Configuration = 'release',
    [Alias('p')][string]$Platform = 'x64',
    [Alias('v')][string]$LibraryVersion = '',
    [Alias('r')][string]$ReleaseVersion = '',
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
Usage: ./scripts/build_windows_library_dll.ps1 [-Module <name>]... [-Configuration <debug|release>] [-Platform <x64>] [-LibraryVersion <version>] [-ReleaseVersion <version>] [-Output <path>] [-Package] [-Nuget <path>]
  -m, -Module          module to build (repeatable): WindowsLibraryCore, WindowsLibraryCApi (default: both)
  -c, -Configuration   debug or release (default: release)
  -p, -Platform        MSBuild platform (default: x64)
  -v, -LibraryVersion  library version; must match the module's public headers
  -r, -ReleaseVersion  version of the dist/<release>/ folder (default: -LibraryVersion)
  -o, -Output          output path (single module only; .lib/.dll, headers and package written alongside)
      -Package         pack the module's NuGet package
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
    'WindowsLibraryCore' = @{
        Kind          = 'static'
        Project       = 'windows\WindowsLibrary\WindowsLibraryCore.vcxproj'
        # The library's own name. The project appends -Debug in Debug builds.
        TargetName    = 'WindowsLibraryCore'
        Prefix        = 'windows-native-toolkit'
        # Every public header, shipped as include\NativeToolkit\<name>.h.
        HeaderDir     = 'windows\WindowsLibrary\include\NativeToolkit'
        # Where the headers declare the version.
        VersionHeader = 'windows\WindowsLibrary\include\NativeToolkit\BuildStamp.h'
        VersionMacro  = 'NATIVETOOLKIT_VERSION'
        Packable      = $true
        PackageId     = 'NativeToolkit'
        NuspecDir     = 'nuget\NativeToolkit'
    }
    'WindowsLibraryCApi' = @{
        Kind          = 'dll'
        Project       = 'windows\WindowsLibraryCApi\WindowsLibraryCApi.vcxproj'
        Def           = 'windows\WindowsLibraryCApi\WindowsLibraryCApi.def'
        Rc            = 'windows\WindowsLibraryCApi\WindowsLibraryCApi.rc'
        # The DLL's own name: the import library loads this, whatever the
        # distributable copy is called.
        DllName       = 'NativeToolkitC'
        Prefix        = 'windows-native-toolkit-capi'
        HeaderDir     = 'windows\WindowsLibraryCApi\include\NativeToolkitC'
        VersionHeader = 'windows\WindowsLibraryCApi\include\NativeToolkitC\Common.h'
        VersionMacro  = 'NTK_VERSION'
        Packable      = $true
        PackageId     = 'NativeToolkit.CApi'
        NuspecDir     = 'nuget\NativeToolkitCApi'
    }
}

# ---------------------------------------------------------------------------
# Validate options (parity with the macOS script)
# ---------------------------------------------------------------------------

$Configuration = $Configuration.ToLowerInvariant()
if ($Configuration -ne 'debug' -and $Configuration -ne 'release') {
    Fail "Configuration must be 'debug' or 'release'."
}

if (-not $Module -or $Module.Count -eq 0) { $Module = @('WindowsLibraryCore', 'WindowsLibraryCApi') }

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

foreach ($name in 'LibraryVersion', 'ReleaseVersion') {
    $value = (Get-Variable -Name $name -ValueOnly)
    if (-not [string]::IsNullOrEmpty($value) -and $value -match '[\s/]') {
        Show-Usage
        Fail "-$name must not contain spaces or '/' characters."
    }
}

if (-not $OutputSet -and [string]::IsNullOrEmpty($LibraryVersion)) {
    Show-Usage
    Fail "-LibraryVersion is required when -Output is not specified."
}

if ($Package -and [string]::IsNullOrEmpty($LibraryVersion)) {
    Fail "-LibraryVersion is required with -Package (used as the NuGet package version)."
}

# The version the headers declare, as "major.minor.patch".
function Get-HeaderVersion([string]$headerPath, [string]$macro) {
    if (-not (Test-Path $headerPath)) { Fail "Version header not found: $headerPath" }
    $text = [System.IO.File]::ReadAllText($headerPath)
    $parts = foreach ($part in 'MAJOR', 'MINOR', 'PATCH') {
        $match = [regex]::Match($text, "#define\s+${macro}_$part\s+(\d+)")
        if (-not $match.Success) { Fail "${macro}_$part not found in $headerPath" }
        $match.Groups[1].Value
    }
    return ($parts -join '.')
}

if (-not [string]::IsNullOrEmpty($LibraryVersion)) {
    foreach ($m in $Module) {
        $cfg = $ModuleConfig[$m]
        $declared = Get-HeaderVersion (Join-Path $RepoRoot $cfg.VersionHeader) $cfg.VersionMacro
        if ($LibraryVersion -ne $declared) {
            Fail "-LibraryVersion $LibraryVersion differs from the version [$m] declares ($declared). Change $($cfg.VersionMacro)_* in $(Split-Path -Leaf $cfg.VersionHeader) first."
        }
    }
}

# The dist/<release>/ folder. The repository's release version, not this
# library's: dist/1.11.0/android holds android-native-toolkit-1.3.0.aar.
$DistVersion = if (-not [string]::IsNullOrEmpty($ReleaseVersion)) { $ReleaseVersion } else { $LibraryVersion }

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
# Build one module in one configuration -> its outputs in $stageDir
# ---------------------------------------------------------------------------

function Build-Module([hashtable]$cfg, [string]$stageDir, [string]$msbuildConfig) {
    $projectPath = Join-Path $RepoRoot $cfg.Project
    if (-not (Test-Path $projectPath)) { Fail "Project not found: $projectPath" }

    $isDll = $cfg.Kind -eq 'dll'
    $tempDef = $null

    if ($isDll) {
        $defPath = Join-Path $RepoRoot $cfg.Def
        if (-not (Test-Path $defPath)) { Fail "DEF file not found: $defPath" }

        # Stage a temporary DEF with the distributable LIBRARY name so the DLL/lib
        # are emitted as <DllName>.dll / <DllName>.lib.
        $tempDef = Join-Path ([System.IO.Path]::GetTempPath()) "$($cfg.DllName).def"
        $defLines = Get-Content -LiteralPath $defPath
        $defLines = $defLines | ForEach-Object {
            if ($_ -match '^\s*LIBRARY') { "LIBRARY $($cfg.DllName)" } else { $_ }
        }
        Set-Content -LiteralPath $tempDef -Value $defLines -Encoding ASCII

        # Stamp the source version resource (FILEVERSION / PRODUCTVERSION) from the
        # library version and persist it, mirroring the macOS pbxproj version update.
        if (-not [string]::IsNullOrEmpty($LibraryVersion) -and -not [string]::IsNullOrEmpty($cfg.Rc)) {
            Update-RcVersion (Join-Path $RepoRoot $cfg.Rc) $LibraryVersion
        }
    }

    if (Test-Path $stageDir) { Remove-Item -Recurse -Force $stageDir }
    New-Item -ItemType Directory -Force -Path $stageDir | Out-Null
    $outDir = (Resolve-Path $stageDir).Path
    if (-not $outDir.EndsWith('\')) { $outDir = "$outDir\" }

    # Override props: disable type-library registration, and for the DLL inject
    # the temp DEF and name the output. The props reach every project the build
    # touches, the static core included, so everything but the registration is
    # conditioned on the module's own project: a global /p:TargetName would
    # rename the core's .lib too, into the import library's name.
    $projectName = [System.IO.Path]::GetFileNameWithoutExtension($cfg.Project)
    $stamp = if ($isDll) { $cfg.DllName } else { $cfg.TargetName }
    $tempProps = Join-Path ([System.IO.Path]::GetTempPath()) "$stamp.$msbuildConfig.override.props"

    $dllProps = if ($isDll) {
@"
    <NativeToolkitTempDef>$tempDef</NativeToolkitTempDef>
    <TargetName>$($cfg.DllName)</TargetName>
"@
    } else { '' }

    $dllItems = if ($isDll) {
@"
  <ItemDefinitionGroup Condition="'`$(MSBuildProjectName)'=='$projectName'">
    <Link>
      <ModuleDefinitionFile>`$(NativeToolkitTempDef)</ModuleDefinitionFile>
    </Link>
  </ItemDefinitionGroup>
"@
    } else { '' }

    $propsContent = @"
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup Condition="'`$(MSBuildProjectName)'=='$projectName'">
$dllProps    <OutDir>$outDir</OutDir>
  </PropertyGroup>
  <ItemDefinitionGroup>
    <Link>
      <RegisterOutput>false</RegisterOutput>
    </Link>
  </ItemDefinitionGroup>
$dllItems</Project>
"@
    Set-Content -LiteralPath $tempProps -Value $propsContent -Encoding UTF8

    Write-Step 'build' "MSBuild $projectName ($msbuildConfig|$Platform)"
    & $MSBuild $projectPath /t:Build /p:Configuration=$msbuildConfig /p:Platform=$Platform `
        /p:ForceImportBeforeCppTargets=$tempProps /nologo /v:minimal | Out-Host
    $buildExit = $LASTEXITCODE

    if ($tempDef) { Remove-Item -LiteralPath $tempDef -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $tempProps -Force -ErrorAction SilentlyContinue

    if ($buildExit -ne 0) { Fail "[$projectName] Build failed (exit $buildExit)." }

    if ($isDll) {
        $dll = Join-Path $outDir "$($cfg.DllName).dll"
        $lib = Join-Path $outDir "$($cfg.DllName).lib"
        if (-not (Test-Path $dll)) { Fail "[$projectName] Output not found: $dll" }
        if (-not (Test-Path $lib)) { Fail "[$projectName] Output not found: $lib" }

        # Drop intermediate link artifacts.
        Remove-Item -Path (Join-Path $outDir "$($cfg.DllName).exp") -Force -ErrorAction SilentlyContinue

        return [pscustomobject]@{ Dll = $dll; Lib = $lib; Configuration = $msbuildConfig }
    }

    # The static library keeps the name its project gives it, which carries a
    # -Debug suffix in Debug builds.
    $libs = @(Get-ChildItem -LiteralPath $outDir -Filter "$($cfg.TargetName)*.lib" -File)
    if ($libs.Count -ne 1) {
        Fail "[$projectName] Expected one $($cfg.TargetName)*.lib in $outDir, found $($libs.Count)."
    }
    return [pscustomobject]@{ Dll = $null; Lib = $libs[0].FullName; Configuration = $msbuildConfig }
}

# ---------------------------------------------------------------------------
# Pack the module's NuGet package from scripts/nuget/<template>
# ---------------------------------------------------------------------------

function Invoke-NugetPack([hashtable]$cfg, [hashtable]$builtByConfig, [string]$nupkgTarget) {
    $nuget = Resolve-Nuget
    $templateDir = Join-Path $PSScriptRoot $cfg.NuspecDir
    if (-not (Test-Path $templateDir)) { Fail "NuGet template not found: $templateDir" }

    # Stage a packing layout next to a copy of the template.
    $packDir = Join-Path ([System.IO.Path]::GetTempPath()) "nupkg-$($cfg.PackageId)-$LibraryVersion"
    if (Test-Path $packDir) { Remove-Item -Recurse -Force $packDir }
    New-Item -ItemType Directory -Force -Path $packDir | Out-Null

    Copy-Item -Recurse -Force (Join-Path $templateDir '*') $packDir

    if ($cfg.Kind -eq 'dll') {
        # The DLL and its import library, under the x64 runtime path.
        $nativeDir = Join-Path $packDir 'runtimes\win-x64\native'
        New-Item -ItemType Directory -Force -Path $nativeDir | Out-Null
        $built = $builtByConfig['Release']
        if (-not $built) { $built = $builtByConfig.Values | Select-Object -First 1 }
        Copy-Item -Force $built.Dll (Join-Path $nativeDir "$($cfg.DllName).dll")
        Copy-Item -Force $built.Lib (Join-Path $nativeDir "$($cfg.DllName).lib")
    } else {
        # Both configurations of the static library: a consumer's Debug build
        # links the Debug one (different CRT and iterator debug level).
        foreach ($c in 'Release', 'Debug') {
            $built = $builtByConfig[$c]
            if (-not $built) { Fail "[$($cfg.PackageId)] The package needs the $c library, which was not built." }
            $libDir = Join-Path $packDir "build\native\lib\x64\$c"
            New-Item -ItemType Directory -Force -Path $libDir | Out-Null
            Copy-Item -Force $built.Lib $libDir
        }
    }

    # Stage the public headers as include\<leaf>\*.h; the nuspec copies the tree
    # to build\native\include, so a consumer writes #include <<leaf>/Name.h>.
    $headerSource = Join-Path $RepoRoot $cfg.HeaderDir
    $includeDir = Join-Path $packDir ('include\' + (Split-Path -Leaf $cfg.HeaderDir))
    New-Item -ItemType Directory -Force -Path $includeDir | Out-Null
    $headers = @(Get-ChildItem -LiteralPath $headerSource -Filter '*.h' -File -ErrorAction SilentlyContinue)
    if ($headers.Count -eq 0) { Fail "[$($cfg.PackageId)] No public headers in $headerSource" }
    foreach ($h in $headers) { Copy-Item -Force $h.FullName $includeDir }

    # Pack to a temp dir (nuget names it <id>.<version>.nupkg), then move the
    # package to the requested target path/name (next to the distributable).
    $packOut = Join-Path $packDir '_out'
    New-Item -ItemType Directory -Force -Path $packOut | Out-Null

    Write-Step 'package' "nuget pack $($cfg.PackageId) $LibraryVersion"
    $nuspec = Join-Path $packDir "$($cfg.PackageId).nuspec"
    if (-not (Test-Path $nuspec)) { Fail "Nuspec not found in template: $nuspec" }
    & $nuget pack $nuspec -Version $LibraryVersion -OutputDirectory $packOut -NonInteractive -Verbosity quiet | Out-Host
    $packExit = $LASTEXITCODE
    if ($packExit -ne 0) { Remove-Item -Recurse -Force $packDir -ErrorAction SilentlyContinue; Fail "nuget pack failed (exit $packExit)." }

    $produced = Join-Path $packOut "$($cfg.PackageId).$LibraryVersion.nupkg"
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
        Fail "[$moduleName] has no NuGet package. Remove -Package."
    }

    Write-Step 'info' "[$moduleName] Building ($MsbuildConfig|$Platform) version=$(if ($LibraryVersion) { $LibraryVersion } else { 'n/a' })"

    # The static library's package carries both configurations.
    $configsToBuild = @($MsbuildConfig)
    if ($Package -and $cfg.Kind -eq 'static') {
        $configsToBuild = @('Release', 'Debug')
    }

    $stageRoot = Join-Path $RepoRoot "windows\Build\$moduleName"
    Write-Step 'clean' "[$moduleName] Cleaning build staging"
    if (Test-Path $stageRoot) { Remove-Item -Recurse -Force $stageRoot }

    $builtByConfig = @{}
    foreach ($c in $configsToBuild) {
        $builtByConfig[$c] = Build-Module $cfg (Join-Path $stageRoot $c) $c
    }
    $built = $builtByConfig[$MsbuildConfig]

    # Resolve the distributable output path.
    $extension = if ($cfg.Kind -eq 'dll') { '.dll' } else { '.lib' }
    if ($OutputSet) {
        $target = if ([System.IO.Path]::IsPathRooted($Output)) { $Output } else { Join-Path $RepoRoot $Output }
    } else {
        $suffix = if ($Configuration -eq 'debug') { "-debug" } else { "" }
        $fileName = "$($cfg.Prefix)-$LibraryVersion$suffix$extension"
        $target = Join-Path $RepoRoot "dist\$DistVersion\windows\$fileName"
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    if ($cfg.Kind -eq 'dll') {
        $libTarget = [System.IO.Path]::ChangeExtension($target, '.lib')
        Copy-Item -Force $built.Dll $target
        Copy-Item -Force $built.Lib $libTarget
        Write-Step 'done' "[$moduleName] Created $target and $libTarget"
    } else {
        Copy-Item -Force $built.Lib $target
        Write-Step 'done' "[$moduleName] Created $target"
    }

    # The public headers, next to the distributable as include\<leaf>\*.h.
    $headerSource = Join-Path $RepoRoot $cfg.HeaderDir
    $headerTarget = Join-Path (Split-Path -Parent $target) ("include\" + (Split-Path -Leaf $cfg.HeaderDir))
    $headers = @(Get-ChildItem -LiteralPath $headerSource -Filter '*.h' -File -ErrorAction SilentlyContinue)
    if ($headers.Count -eq 0) { Fail "[$moduleName] No public headers in $headerSource" }
    New-Item -ItemType Directory -Force -Path $headerTarget | Out-Null
    foreach ($h in $headers) { Copy-Item -Force $h.FullName $headerTarget }
    Write-Step 'done' "[$moduleName] Copied $($headers.Count) headers to $headerTarget"

    if ($Package) {
        # Place the package next to the distributable with the same base name.
        $nupkgTarget = [System.IO.Path]::ChangeExtension($target, '.nupkg')
        $nupkg = Invoke-NugetPack $cfg $builtByConfig $nupkgTarget
        Write-Step 'done' "[$moduleName] Created $nupkg"
    }
}
