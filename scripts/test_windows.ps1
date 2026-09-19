<#
.SYNOPSIS
  Runs every automated Windows test: the library unit tests and the UI tests
  of the sample app.

.DESCRIPTION
  1. Builds WindowsLibrary + WindowsLibraryTest and runs the unit tests with
     vstest.console.exe.
  2. Builds WindowsLibraryExample and registers its AppX layout, so the UI
     tests always run against the build just made (a plain MSBuild does not
     update the registered layout; this does what Visual Studio's Deploy does).
  3. Runs WindowsLibraryExampleUITest.
  4. Checks that the Windows settings the UI tests changed were put back.
  5. Prints the counts and failures, and compares every test's outcome with
     the saved baseline (scripts/test_windows.baseline.json).

  The UI tests drive the real desktop: do not use the PC while they run, and
  do not lock the screen. The script keeps the display awake while it runs.
  The computer use procedures (windows/WindowsLibraryExampleUITest/ComputerUse)
  are run afterwards from the Claude desktop app.

  See artifact/topics/windows-architecture/designs/2026-09-19-windows-architecture-ui-test-design.md (8).

.PARAMETER IncludeDestructive
  Also runs ClipboardHistoryDestructive, which deletes every unpinned item in
  the user's clipboard history. That cannot be undone.

.PARAMETER Baseline
  Saves this run's outcomes as the new baseline. Only allowed without -Filter
  and without -SkipUnitTests, and only when nothing failed.

.PARAMETER Filter
  dotnet test filter for the UI tests (for example "TestCategory=Dialog").

.PARAMETER SkipUnitTests
  Skips step 1.

.EXAMPLE
  powershell -File scripts\test_windows.ps1

.EXAMPLE
  powershell -File scripts\test_windows.ps1 -Filter "TestCategory=Notification"

.EXAMPLE
  powershell -File scripts\test_windows.ps1 -IncludeDestructive -Baseline
#>
[CmdletBinding()]
param(
    [switch]$IncludeDestructive,
    [switch]$Baseline,
    [string]$Filter = '',
    [switch]$SkipUnitTests
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$WindowsDir = Join-Path $RepoRoot 'windows'
$LibrarySln = Join-Path $WindowsDir 'WindowsLibrary\WindowsLibrary.sln'
$ExampleSln = Join-Path $WindowsDir 'WindowsLibraryExample\WindowsLibraryExample.sln'
$UiTestProject = Join-Path $WindowsDir 'WindowsLibraryExampleUITest\WindowsLibraryExampleUITest.csproj'
$BaselinePath = Join-Path $PSScriptRoot 'test_windows.baseline.json'
$SettingsRecord = Join-Path ([IO.Path]::GetTempPath()) 'ntk-uitest-os-settings.json'
$PackageName = '52870e33-d98c-4b7c-be95-bf290f9eff7b'
$UnitTestConfiguration = 'Debug'
$ExampleConfiguration = 'Release'
$Platform = 'x64'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Step([string]$prefix, [string]$message) {
    Write-Host "[$prefix] $message"
}

function Fail([string]$message) {
    Write-Host "[error] $message" -ForegroundColor Red
    exit 1
}

function Find-VsTool([string]$pattern, [string]$what) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) {
        Fail "vswhere not found. Install Visual Studio (Build Tools or Community)."
    }
    $found = & $vswhere -latest -products * -find $pattern | Select-Object -First 1
    if ([string]::IsNullOrEmpty($found) -or -not (Test-Path $found)) {
        Fail "$what not found via vswhere."
    }
    return $found
}

function Invoke-MSBuild([string]$solution, [string]$configuration) {
    Write-Step 'build' "$(Split-Path -Leaf $solution) ($configuration|$Platform)"
    & $script:MSBuild $solution /t:Build /m /nologo /v:minimal "/p:Configuration=$configuration" "/p:Platform=$Platform"
    if ($LASTEXITCODE -ne 0) {
        Fail "MSBuild failed for $solution (exit code $LASTEXITCODE)."
    }
}

Add-Type -Namespace NtkTestWindows -Name Native -MemberDefinition @'
[DllImport("kernel32.dll")]
public static extern uint SetThreadExecutionState(uint flags);

[DllImport("user32.dll", SetLastError = true)]
public static extern System.IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);

[DllImport("user32.dll")]
public static extern bool CloseDesktop(System.IntPtr desktop);

[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern bool GetUserObjectInformation(System.IntPtr obj, int index, System.Text.StringBuilder info, int length, out int needed);
'@

# True when the input desktop is the user's desktop. While the screen is
# locked it is the Winlogon desktop, or it cannot be opened at all.
function Test-DesktopUnlocked {
    $desktop = [NtkTestWindows.Native]::OpenInputDesktop(0, $false, 0x0001) # DESKTOP_READOBJECTS
    if ($desktop -eq [IntPtr]::Zero) {
        return $false
    }
    try {
        $name = New-Object System.Text.StringBuilder 256
        $needed = 0
        [void][NtkTestWindows.Native]::GetUserObjectInformation($desktop, 2, $name, 512, [ref]$needed) # UOI_NAME
        return $name.ToString() -eq 'Default'
    } finally {
        [void][NtkTestWindows.Native]::CloseDesktop($desktop)
    }
}

# ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED. Built from a string:
# PowerShell 5.1 reads the literal 0x80000003 as a negative Int32.
$KeepAwake = [Convert]::ToUInt32('80000003', 16)
$ReleaseAwake = [Convert]::ToUInt32('80000000', 16) # ES_CONTINUOUS alone

function Deploy-Example {
    $out = Join-Path $WindowsDir "WindowsLibraryExample\$Platform\$ExampleConfiguration\WindowsLibraryExample"
    $recipePath = Join-Path $out 'WindowsLibraryExample.build.appxrecipe'
    $layout = Join-Path $out 'AppX'
    if (-not (Test-Path $recipePath)) {
        Fail "No recipe at $recipePath after the build."
    }

    # Copy every file the recipe lists into the AppX layout, as Visual Studio's
    # Deploy does. Compiled XAML is inside resources.pri, which is listed.
    [xml]$recipe = Get-Content -LiteralPath $recipePath -Raw
    $items = $recipe.SelectNodes("//*[local-name()='AppxPackagedFile' or local-name()='AppXManifest']")
    $copied = 0
    foreach ($item in $items) {
        $source = (Resolve-Path -LiteralPath $item.GetAttribute('Include')).Path
        $target = Join-Path $layout $item.PackagePath
        if ([string]::Equals($source, $target, [StringComparison]::OrdinalIgnoreCase)) {
            continue # already produced inside the layout
        }
        New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
        Copy-Item -LiteralPath $source -Destination $target -Force
        $copied++
    }

    Add-AppxPackage -Register (Join-Path $layout 'AppxManifest.xml') -ForceApplicationShutdown
    $package = Get-AppxPackage -Name $PackageName | Select-Object -First 1
    if ($null -eq $package -or -not [string]::Equals($package.InstallLocation, $layout, [StringComparison]::OrdinalIgnoreCase)) {
        Fail "The sample is not registered from $layout."
    }
    Write-Step 'deploy' "Registered $($package.PackageFamilyName) ($copied of $($items.Count) recipe items copied)"
}

# Reads a TRX file into "Class.Method" -> outcome.
function Read-Trx([string]$path) {
    [xml]$trx = Get-Content -LiteralPath $path -Raw
    $classes = @{}
    foreach ($test in $trx.SelectNodes("//*[local-name()='UnitTest']")) {
        $method = $test.SelectSingleNode("*[local-name()='TestMethod']")
        $classes[$test.GetAttribute('id')] = $method.GetAttribute('className')
    }
    $outcomes = [ordered]@{}
    foreach ($result in $trx.SelectNodes("//*[local-name()='UnitTestResult']")) {
        $class = $classes[$result.GetAttribute('testId')]
        $short = if ($class) { ($class -split '[.,]')[-1].Trim() } else { '' }
        $name = if ($short) { "$short.$($result.GetAttribute('testName'))" } else { $result.GetAttribute('testName') }
        $outcomes[$name] = $result.GetAttribute('outcome')
    }
    return $outcomes
}

function Find-Trx([string]$directory) {
    $file = Get-ChildItem -LiteralPath $directory -Filter '*.trx' -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($null -eq $file) {
        Fail "No test results (.trx) under $directory."
    }
    return $file.FullName
}

function Write-Summary([string]$suite, $outcomes) {
    $groups = $outcomes.Values | Group-Object | Sort-Object Name
    $counts = ($groups | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', '
    Write-Step $suite "$($outcomes.Count) tests: $counts"
    foreach ($key in $outcomes.Keys) {
        if ($outcomes[$key] -eq 'Failed') {
            Write-Host "  FAILED $key" -ForegroundColor Red
        }
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if ($Baseline -and ($Filter -or $SkipUnitTests)) {
    Fail "-Baseline needs a full run: do not combine it with -Filter or -SkipUnitTests."
}

if (-not (Test-DesktopUnlocked)) {
    Fail "The screen is locked. Unlock it and run again: the UI tests need the desktop."
}

if (Test-Path $SettingsRecord) {
    Write-Step 'settings' "An earlier run left Windows settings changed ($SettingsRecord). The UI tests put them back first."
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$ResultsDir = Join-Path $WindowsDir "WindowsLibraryExampleUITest\TestResults\test_windows\$stamp"
New-Item -ItemType Directory -Force -Path $ResultsDir | Out-Null

$MSBuild = Find-VsTool 'MSBuild\**\Bin\MSBuild.exe' 'MSBuild'
$started = Get-Date
$results = [ordered]@{}

[void][NtkTestWindows.Native]::SetThreadExecutionState($KeepAwake)
try {
    # 1. Unit tests
    if (-not $SkipUnitTests) {
        Invoke-MSBuild $LibrarySln $UnitTestConfiguration
        $vstest = Find-VsTool '**\TestPlatform\vstest.console.exe' 'vstest.console.exe'
        $unitDll = Join-Path $WindowsDir "WindowsLibrary\$Platform\$UnitTestConfiguration\WindowsLibraryTest.dll"
        if (-not (Test-Path $unitDll)) {
            Fail "Unit test DLL not found at $unitDll."
        }
        $unitResults = Join-Path $ResultsDir 'unit'
        Write-Step 'unit' "vstest.console $unitDll"
        & $vstest $unitDll '/Logger:trx' "/ResultsDirectory:$unitResults" | Out-Host
        $unit = Read-Trx (Find-Trx $unitResults)
        foreach ($key in $unit.Keys) { $results["unit/$key"] = $unit[$key] }
        Write-Summary 'unit' $unit
    }

    # 2. Sample app
    Invoke-MSBuild $ExampleSln $ExampleConfiguration
    Deploy-Example

    # 3. UI tests
    if (-not (Test-DesktopUnlocked)) {
        Fail "The screen got locked during the build. Unlock it and run again."
    }
    $previousOptIn = $env:NTK_UITEST_DESTRUCTIVE
    $env:NTK_UITEST_DESTRUCTIVE = if ($IncludeDestructive) { '1' } else { '' }
    try {
        $uiResults = Join-Path $ResultsDir 'ui'
        $dotnetArgs = @('test', $UiTestProject, '--nologo', '--logger', 'trx', '--results-directory', $uiResults)
        if ($Filter) { $dotnetArgs += @('--filter', $Filter) }
        $described = 'dotnet test'
        if ($Filter) { $described += " --filter '$Filter'" }
        if ($IncludeDestructive) { $described += ' (destructive included)' }
        Write-Step 'ui' $described
        & dotnet @dotnetArgs | Out-Host
    } finally {
        $env:NTK_UITEST_DESTRUCTIVE = $previousOptIn
    }
    $ui = Read-Trx (Find-Trx $uiResults)
    foreach ($key in $ui.Keys) { $results["ui/$key"] = $ui[$key] }
    Write-Summary 'ui' $ui
} finally {
    [void][NtkTestWindows.Native]::SetThreadExecutionState($ReleaseAwake)
}

# 4. Windows settings
$settingsOk = -not (Test-Path $SettingsRecord)
if ($settingsOk) {
    Write-Step 'settings' 'All changed Windows settings were put back.'
} else {
    Write-Host "[settings] Windows settings are still changed; see $SettingsRecord. The next run puts them back, or follows its instructions." -ForegroundColor Red
}

# 5. Summary and baseline
$failed = @($results.Keys | Where-Object { $results[$_] -eq 'Failed' })
$elapsed = (Get-Date) - $started
Write-Step 'done' ("{0} tests, {1} failed, {2:mm\:ss} elapsed. Results: {3}" -f $results.Count, $failed.Count, $elapsed, $ResultsDir)

$differences = @()
if (Test-Path $BaselinePath) {
    $saved = Get-Content -LiteralPath $BaselinePath -Raw | ConvertFrom-Json
    $expected = @{}
    foreach ($p in $saved.outcomes.PSObject.Properties) { $expected[$p.Name] = $p.Value }
    foreach ($key in $results.Keys) {
        if (-not $expected.ContainsKey($key)) {
            $differences += "  new       $key ($($results[$key]))"
        } elseif ($expected[$key] -ne $results[$key]) {
            $differences += "  changed   $key ($($expected[$key]) -> $($results[$key]))"
        }
    }
    if (-not $Filter -and -not $SkipUnitTests) {
        foreach ($key in $expected.Keys) {
            if (-not $results.Contains($key)) {
                $differences += "  missing   $key (was $($expected[$key]))"
            }
        }
    }
    if ($differences.Count -eq 0) {
        Write-Step 'baseline' "Same outcomes as the baseline of $($saved.recordedAt)."
    } else {
        Write-Host "[baseline] Differences from the baseline of $($saved.recordedAt):" -ForegroundColor Yellow
        $differences | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
    }
} else {
    Write-Step 'baseline' "No baseline yet ($BaselinePath). Save one with -Baseline."
}

if ($Baseline) {
    if ($failed.Count -gt 0 -or -not $settingsOk) {
        Fail 'Not saving a baseline from a run with failures or changed settings.'
    }
    $record = [ordered]@{
        recordedAt = (Get-Date -Format 'yyyy-MM-dd HH:mm')
        commit = (& git -C $RepoRoot rev-parse --short HEAD)
        includeDestructive = [bool]$IncludeDestructive
        outcomes = $results
    }
    # UTF-8 without BOM, so that git and other tools read it as plain text.
    [IO.File]::WriteAllText($BaselinePath, ($record | ConvertTo-Json -Depth 3), (New-Object System.Text.UTF8Encoding $false))
    Write-Step 'baseline' "Saved $($results.Count) outcomes to $BaselinePath."
}

if ($failed.Count -gt 0 -or -not $settingsOk) {
    exit 1
}
exit 0
