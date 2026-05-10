# apply_patches_r6.ps1
# Round 6 - definitive fixes for the two remaining issues:
#
#  1. Polygon/wingdi: add NOGDI before windows.h in Misc.h
#     This prevents wingdi.h from loading at all, killing Polygon() at source.
#
#  2. Agency.h _timezone member: rename _timezone member to _tz throughout
#     Agency.h. The `timezone` macro transforms `_timezone` to `__timezone()`
#     because MinGW defines:  #define timezone  _timezone
#     So `_timezone` expands to `__timezone`. Renaming the member to `_tz`
#     breaks this entirely.
#
# Run from the ROOT of your loom repo:
#   cd D:\path\to\loom
#   ..\loom-patches-r6\apply_patches_r6.ps1

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot  = (Get-Location).Path

Write-Host ""
Write-Host "=== LOOM Windows Patch Script - Round 6 ===" -ForegroundColor Cyan
Write-Host "Repo root : $RepoRoot"
Write-Host ""

# -----------------------------------------------------------------------
# FIX 1: Misc.h — add NOGDI before windows.h
#
# NOGDI tells windows.h to skip wingdi.h entirely.
# wingdi.h is only needed for graphics programming.
# LOOM only uses windows.h for file I/O, process, and console functions
# — none of which need GDI. This is safe.
#
# We also add NOUSER (skips user32 stuff like MessageBox) and
# NOSOUND (skips mmsystem) to keep the header lean.
# -----------------------------------------------------------------------
Write-Host "[1/2] Patching src/util/Misc.h (add NOGDI before windows.h)..." -ForegroundColor Yellow

$miscHPath = Join-Path $RepoRoot "src\util\Misc.h"
if (-not (Test-Path $miscHPath)) {
    $found = Get-ChildItem -Path (Join-Path $RepoRoot "src\util") -Filter "Misc.h" -ErrorAction SilentlyContinue
    if ($found) { $miscHPath = $found[0].FullName }
}

if (Test-Path $miscHPath) {
    $c = [IO.File]::ReadAllText($miscHPath)

    if ($c.Contains('NOGDI')) {
        Write-Host "  already has NOGDI: Misc.h" -ForegroundColor DarkGray
    } else {
        $nogdiBlock = @"
// WIN32 PATCH R6: define NOGDI before windows.h to prevent wingdi.h
// from loading. wingdi.h defines Polygon(), Rectangle() etc. as GDI
// functions which clash with util::geo::Polygon and other LOOM types.
// LOOM only uses windows.h for file I/O and process functions, not GDI.
#ifdef _WIN32
#ifndef NOGDI
#define NOGDI
#endif
#ifndef NOUSER
#define NOUSER
#endif
#ifndef NOSOUND
#define NOSOUND
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#endif
// END WIN32 PATCH R6
"@

        # Find the #include <windows.h> line and insert NOGDI defines before it
        $winInclude = ($c -split "`n" | Where-Object { $_ -match '#include\s*<windows\.h>' } | Select-Object -First 1)

        if ($winInclude) {
            $c = $c.Replace($winInclude, $nogdiBlock + "`n" + $winInclude)
            [IO.File]::WriteAllText($miscHPath, $c, [Text.Encoding]::UTF8)
            Write-Host "  PATCHED: added NOGDI before #include <windows.h>" -ForegroundColor Green
        } else {
            Write-Host "  WARNING: #include <windows.h> not found directly in Misc.h" -ForegroundColor Yellow
            Write-Host "  Appending NOGDI define at top of file instead..." -ForegroundColor Yellow
            # Prepend to file
            $c = $nogdiBlock + "`n" + $c
            [IO.File]::WriteAllText($miscHPath, $c, [Text.Encoding]::UTF8)
            Write-Host "  PATCHED (prepended): Misc.h" -ForegroundColor Green
        }
    }
} else {
    Write-Host "  ERROR: Misc.h not found" -ForegroundColor Red
}

# Also add NOGDI to win_compat.h before its windows.h include, for consistency
$winCompatPath = Join-Path $RepoRoot "win_compat.h"
if (Test-Path $winCompatPath) {
    $c = [IO.File]::ReadAllText($winCompatPath)
    if (-not $c.Contains('NOGDI')) {
        $c = $c.Replace(
            '#include <winsock2.h>',
            '// WIN32 PATCH R6: NOGDI prevents wingdi.h (Polygon clash)' + "`n" +
            '#ifndef NOGDI' + "`n#define NOGDI`n#endif`n" +
            '#include <winsock2.h>')
        [IO.File]::WriteAllText($winCompatPath, $c, [Text.Encoding]::UTF8)
        Write-Host "  PATCHED: win_compat.h (added NOGDI)" -ForegroundColor Green
    }
}

# -----------------------------------------------------------------------
# FIX 2: Agency.h — rename member _timezone to _tz throughout
#
# The Windows time.h macro: #define timezone _timezone
# means that wherever the compiler sees `_timezone` as an identifier,
# it gets macro-expanded. The member name `_timezone` gets turned into
# `__timezone` (because _timezone -> __timezone through a double-expand).
#
# Renaming the member `_timezone` -> `_tz` throughout Agency.h is the
# only clean fix. This affects: the member declaration, constructor
# initializer lists, getTimezone(), getFlat(), and setTimezone().
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "[2/2] Patching Agency.h (rename member _timezone -> _tz)..." -ForegroundColor Yellow

$agencyPath = Join-Path $RepoRoot "src\cppgtfs\src\ad\cppgtfs\gtfs\Agency.h"
if (-not (Test-Path $agencyPath)) {
    $found = Get-ChildItem -Path (Join-Path $RepoRoot "src") -Recurse -Filter "Agency.h" -ErrorAction SilentlyContinue
    if ($found) {
        $agencyPath = $found[0].FullName
        Write-Host "  Found Agency.h at: $agencyPath" -ForegroundColor Cyan
    }
}

if (Test-Path $agencyPath) {
    $c = [IO.File]::ReadAllText($agencyPath)

    if ($c.Contains('WIN32 PATCH R6: _timezone->_tz')) {
        Write-Host "  already patched: Agency.h" -ForegroundColor DarkGray
    } else {
        $marker = "// WIN32 PATCH R6: _timezone->_tz (Windows time.h macro clash)`n"

        # Count occurrences to verify we're finding them
        $count = ([regex]::Matches($c, '_timezone')).Count
        Write-Host "  Found $count occurrences of _timezone in Agency.h" -ForegroundColor Cyan

        # Rename ALL occurrences of _timezone to _tz
        # This covers: member declaration, initializer lists, getters, setters, getFlat()
        $c2 = $c.Replace('_timezone', '_tz')

        if ($c2 -ne $c) {
            $c2 = $marker + $c2
            [IO.File]::WriteAllText($agencyPath, $c2, [Text.Encoding]::UTF8)
            Write-Host "  PATCHED: renamed _timezone -> _tz ($count occurrences)" -ForegroundColor Green
        } else {
            Write-Host "  WARNING: no _timezone found in Agency.h" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "  ERROR: Agency.h not found" -ForegroundColor Red
}

# -----------------------------------------------------------------------
# Also check for other files in cppgtfs that reference Agency._timezone
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "Checking for other cppgtfs files that access _timezone..." -ForegroundColor Yellow
$cppgtfsFiles = Get-ChildItem -Path (Join-Path $RepoRoot "src\cppgtfs") -Recurse -Include "*.h","*.cpp" -ErrorAction SilentlyContinue
$affectedFiles = @()
foreach ($f in $cppgtfsFiles) {
    $content = [IO.File]::ReadAllText($f.FullName)
    if ($content.Contains('_timezone') -and $f.Name -ne 'Agency.h') {
        $affectedFiles += $f
    }
}

if ($affectedFiles.Count -gt 0) {
    Write-Host "  Found _timezone in:" -ForegroundColor Yellow
    foreach ($f in $affectedFiles) {
        Write-Host "    $($f.FullName)" -ForegroundColor Yellow
        $c = [IO.File]::ReadAllText($f.FullName)
        $c2 = $c.Replace('_timezone', '_tz')
        if ($c2 -ne $c) {
            [IO.File]::WriteAllText($f.FullName, $c2, [Text.Encoding]::UTF8)
            Write-Host "    -> patched" -ForegroundColor Green
        }
    }
} else {
    Write-Host "  No other files affected." -ForegroundColor Green
}

# -----------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "=== Round 6 patches applied! ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Rebuild with:" -ForegroundColor White
Write-Host "  cd build" -ForegroundColor Yellow
Write-Host "  mingw32-make -j`$(nproc) 2>&1 | tee build_log_r6.txt" -ForegroundColor Yellow
Write-Host ""
Write-Host "NOGDI eliminates the Polygon/wingdi clash at the root." -ForegroundColor White
Write-Host "Renaming _timezone to _tz eliminates the macro expansion." -ForegroundColor White
Write-Host ""
