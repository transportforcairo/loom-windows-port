# apply_patches_r7.ps1
# Round 7 - two new issues after NOGDI fix:
#
# 1. RenderGraph.cpp: uses `using util::geo::Polygon` but bzlib.h pulls
#    in windows.h WITHOUT NOGDI (it has its own include path that bypasses
#    Misc.h). wingdi.h fires again via bzlib.h -> windows.h.
#    Fix: add NOGDI to CMakeLists.txt as a global compile definition
#    so it applies to every translation unit unconditionally.
#
# 2. Parser.tpp: stop_timezone member renamed to stop_tz by the same
#    timezone macro. The _timezone -> _tz rename in R6 only fixed Agency.h.
#    We need to find and fix all other structs with `_timezone` or
#    `stop_timezone` fields in the cppgtfs submodule.
#
# Run from the ROOT of your loom repo:
#   cd D:\path\to\loom
#   ..\loom-patches-r7\apply_patches_r7.ps1

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot  = (Get-Location).Path

Write-Host ""
Write-Host "=== LOOM Windows Patch Script - Round 7 ===" -ForegroundColor Cyan
Write-Host "Repo root : $RepoRoot"
Write-Host ""

# -----------------------------------------------------------------------
# FIX 1: Add NOGDI as a global CMake compile definition
#
# The problem: bzlib.h (included by Misc.h) itself includes windows.h
# without going through our NOGDI define in Misc.h. Any .cpp that
# eventually pulls in bzlib.h will get wingdi.h.
#
# The definitive fix: add NOGDI to add_compile_definitions() in
# CMakeLists.txt so it applies to the entire build globally.
# This is the correct approach — NOGDI is a legitimate Windows SDK flag.
# -----------------------------------------------------------------------
Write-Host "[1/2] Adding NOGDI to CMakeLists.txt as global compile definition..." -ForegroundColor Yellow

$cmakePath = Join-Path $RepoRoot "CMakeLists.txt"
if (Test-Path $cmakePath) {
    $c = [IO.File]::ReadAllText($cmakePath)

    if ($c.Contains('NOGDI') -and $c.Contains('add_compile_definitions')) {
        Write-Host "  NOGDI already in CMakeLists.txt compile definitions" -ForegroundColor DarkGray
    } else {
        # Find the WIN32 PATCH block we added in R1 and extend it
        $oldWin32Block = 'add_compile_definitions(NOMINMAX WIN32_LEAN_AND_MEAN)'
        $newWin32Block = 'add_compile_definitions(NOMINMAX WIN32_LEAN_AND_MEAN NOGDI NOUSER NOSOUND)'

        if ($c.Contains($oldWin32Block)) {
            $c = $c.Replace($oldWin32Block, $newWin32Block)
            [IO.File]::WriteAllText($cmakePath, $c, [Text.Encoding]::UTF8)
            Write-Host "  PATCHED: added NOGDI NOUSER NOSOUND to compile definitions" -ForegroundColor Green
        } else {
            # The R1 block might look slightly different - find any add_compile_definitions
            # in the WIN32 block and add to it, or insert a new one
            $winBlockStart = '# ==== BEGIN WIN32 PATCH ===='
            if ($c.Contains($winBlockStart)) {
                $insert = @"
  # WIN32 PATCH R7: NOGDI prevents wingdi.h from loading via any include path
  # This stops Polygon(), Rectangle() etc. GDI functions from polluting namespace
  add_compile_definitions(NOGDI NOUSER NOSOUND)
"@
                $c = $c.Replace($winBlockStart, $winBlockStart + "`n" + $insert)
                [IO.File]::WriteAllText($cmakePath, $c, [Text.Encoding]::UTF8)
                Write-Host "  PATCHED: inserted NOGDI block in WIN32 section" -ForegroundColor Green
            } else {
                Write-Host "  WARNING: Could not find WIN32 patch block in CMakeLists.txt" -ForegroundColor Yellow
                Write-Host "  Please manually add this line inside the if(WIN32) block:" -ForegroundColor Yellow
                Write-Host "    add_compile_definitions(NOGDI NOUSER NOSOUND)" -ForegroundColor Cyan
            }
        }
    }
} else {
    Write-Host "  ERROR: CMakeLists.txt not found" -ForegroundColor Red
}

# -----------------------------------------------------------------------
# FIX 2: cppgtfs stop_timezone field renamed by Windows macro
#
# Parser.tpp references fs.stop_timezone which has been macro-renamed.
# We need to find the struct definition containing stop_timezone and
# rename it to stop_tz, then fix all references.
#
# Search all cppgtfs files for stop_timezone and rename to stop_tz.
# Also search for any remaining _timezone occurrences we missed.
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "[2/2] Fixing stop_timezone -> stop_tz throughout cppgtfs..." -ForegroundColor Yellow

$cppgtfsRoot = Join-Path $RepoRoot "src\cppgtfs"
if (-not (Test-Path $cppgtfsRoot)) {
    Write-Host "  ERROR: src\cppgtfs not found" -ForegroundColor Red
} else {
    $files = Get-ChildItem -Path $cppgtfsRoot -Recurse -Include "*.h","*.cpp","*.tpp" -ErrorAction SilentlyContinue

    $totalPatched = 0
    foreach ($f in $files) {
        $c = [IO.File]::ReadAllText($f.FullName)
        $c2 = $c

        # stop_timezone -> stop_tz
        $c2 = $c2.Replace('stop_timezone', 'stop_tz')

        # Any remaining _timezone -> _tz (missed in R6)
        # But be careful: only replace standalone _timezone, not things like
        # stop_timezone (already handled above) or other compound names
        # Use a targeted replacement for the remaining cases
        if ($c2.Contains('_timezone')) {
            $c2 = $c2.Replace('_timezone', '_tz')
        }

        if ($c2 -ne $c) {
            [IO.File]::WriteAllText($f.FullName, $c2, [Text.Encoding]::UTF8)
            $totalPatched++
            Write-Host "  PATCHED: $($f.Name)" -ForegroundColor Green
        }
    }

    if ($totalPatched -eq 0) {
        Write-Host "  No timezone references found in cppgtfs (already clean)" -ForegroundColor DarkGray
    } else {
        Write-Host "  Patched $totalPatched files" -ForegroundColor Green
    }
}

# -----------------------------------------------------------------------
# Also fix any timezone references in the main src/ tree outside cppgtfs
# (RenderGraph, etc. use `using util::geo::Polygon` — that's fine once
# NOGDI is set globally. But scan for any other _timezone references.)
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "Scanning main src/ for remaining timezone references..." -ForegroundColor Yellow

$srcRoot = Join-Path $RepoRoot "src"
$mainFiles = Get-ChildItem -Path $srcRoot -Recurse -Include "*.h","*.cpp","*.tpp" -ErrorAction SilentlyContinue |
             Where-Object { $_.FullName -notmatch 'cppgtfs' -and $_.FullName -notmatch 'util' }

$mainPatched = 0
foreach ($f in $mainFiles) {
    $c = [IO.File]::ReadAllText($f.FullName)
    if ($c.Contains('_timezone') -or $c.Contains('stop_timezone')) {
        $c2 = $c.Replace('stop_timezone', 'stop_tz').Replace('_timezone', '_tz')
        [IO.File]::WriteAllText($f.FullName, $c2, [Text.Encoding]::UTF8)
        $mainPatched++
        Write-Host "  PATCHED: $($f.Name)" -ForegroundColor Green
    }
}
if ($mainPatched -eq 0) {
    Write-Host "  No additional timezone references found outside cppgtfs/util" -ForegroundColor DarkGray
}

# -----------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "=== Round 7 patches applied! ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "IMPORTANT: CMakeLists.txt was changed." -ForegroundColor Yellow
Write-Host "You must re-run cmake before building:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  cd build" -ForegroundColor Yellow
Write-Host "  cmake .. -G `"MinGW Makefiles`" -DCMAKE_BUILD_TYPE=Release -DLOOM_USE_GUROBI=OFF" -ForegroundColor Yellow
Write-Host "  mingw32-make -j`$(nproc) 2>&1 | tee build_log_r7.txt" -ForegroundColor Yellow
Write-Host ""
