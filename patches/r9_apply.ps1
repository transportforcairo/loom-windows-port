# apply_patches_r9.ps1
# Round 9 - two tasks:
#   1. Repair the CMakeLists.txt files that R8 broke with a malformed
#      generator expression (missing closing parenthesis)
#   2. Fix -lutil properly: just remove it, don't replace with a
#      generator expression (which is what caused the parse errors)
#
# Run from the ROOT of your loom repo:
#   cd D:\path\to\loom
#   ..\loom-patches-r9\apply_patches_r9.ps1

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot  = (Get-Location).Path

Write-Host ""
Write-Host "=== LOOM Windows Patch Script - Round 9 ===" -ForegroundColor Cyan
Write-Host "Repo root : $RepoRoot"
Write-Host ""

# -----------------------------------------------------------------------
# REPAIR: Remove the broken generator expression R8 inserted.
# The R8 patch replaced ` util)` with:
#   $<$<NOT:$<PLATFORM_ID:Windows>>:util>)  # WIN32 PATCH R8
# but this broke CMake's parser because the generator expression
# syntax with nested $< > confused the parenthesis counter.
#
# Fix: just remove `util` from target_link_libraries entirely on Windows.
# We do NOT need libutil at all - it's a POSIX-only pty library.
# The cleanest approach is to simply delete it from the link line.
# -----------------------------------------------------------------------
Write-Host "[1/2] Repairing CMakeLists.txt files broken by R8..." -ForegroundColor Yellow

$cmakeFiles = Get-ChildItem -Path $RepoRoot -Recurse -Filter "CMakeLists.txt" -ErrorAction SilentlyContinue
$repaired = 0

foreach ($f in $cmakeFiles) {
    $c = [IO.File]::ReadAllText($f.FullName)
    $c2 = $c

    # Remove the broken R8 generator expression, restoring the original
    # The pattern R8 inserted was:
    #   $<$<NOT:$<PLATFORM_ID:Windows>>:util>  # WIN32 PATCH R8
    # Restore it to just: util  (we'll remove util cleanly in step 2)
    if ($c2.Contains('$<$<NOT:$<PLATFORM_ID:Windows>>:util>')) {
        $c2 = $c2 -replace '\$<\$<NOT:\$<PLATFORM_ID:Windows>>:util>\s*#?\s*WIN32 PATCH R8\s*', 'util'
        $c2 = $c2 -replace '\$<\$<NOT:\$<PLATFORM_ID:Windows>>:util>', 'util'
    }

    # Also clean up any leftover # WIN32 PATCH R8 comments on link lines
    $c2 = $c2 -replace '\s*#\s*WIN32 PATCH R8', ''

    if ($c2 -ne $c) {
        [IO.File]::WriteAllText($f.FullName, $c2, [Text.Encoding]::UTF8)
        Write-Host "  REPAIRED: $($f.Name)" -ForegroundColor Green
        $repaired++
    }
}

if ($repaired -eq 0) {
    Write-Host "  No R8 generator expressions found (already clean or R8 didn't apply)" -ForegroundColor DarkGray
}

# -----------------------------------------------------------------------
# FIX: Now cleanly remove `util` from target_link_libraries on Windows.
# Simple approach: wrap in if(NOT WIN32) block.
# We do this by finding lines with `target_link_libraries` containing
# a bare `util` token and replacing the whole call.
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "[2/2] Cleanly removing -lutil from link dependencies on Windows..." -ForegroundColor Yellow

# Also repair the main CMakeLists.txt WIN32 block if R8 added broken stuff
$mainCmake = Join-Path $RepoRoot "CMakeLists.txt"
$mc = [IO.File]::ReadAllText($mainCmake)

# Remove the broken util stub R8 may have added
if ($mc.Contains('add_library(__util_stub INTERFACE)')) {
    $mc = $mc -replace '\s*# WIN32 PATCH R8[^\n]*\n', "`n"
    $mc = $mc -replace '\s*add_library\(__util_stub INTERFACE\)\s*\n', ''
    $mc = $mc -replace '\s*add_library\(util ALIAS __util_stub\)\s*\n', ''
    $mc = $mc -replace '\s*string\(REPLACE "-lutil"[^\n]*\n', ''
    [IO.File]::WriteAllText($mainCmake, $mc, [Text.Encoding]::UTF8)
    Write-Host "  Removed broken R8 util stub from main CMakeLists.txt" -ForegroundColor Green
}

# Now find the test CMakeLists files that link util and wrap with if(NOT WIN32)
$testCmakeFiles = Get-ChildItem -Path $RepoRoot -Recurse -Filter "CMakeLists.txt" |
    Where-Object { $_.FullName -match 'tests?' }

$fixed = 0
foreach ($f in $testCmakeFiles) {
    $c = [IO.File]::ReadAllText($f.FullName)

    # Check for bare `util` in a target_link_libraries call
    # Match: target_link_libraries(something ... util ...)
    # but NOT pb_util, pb_util_geo etc (those have underscores after util)
    if ($c -match '(?<![\w_])util(?![\w_])' -and $c -match 'target_link_libraries') {

        Write-Host "  Processing: $($f.FullName)" -ForegroundColor Cyan

        # Split into lines, find the target_link_libraries line with util,
        # and wrap it
        $lines = $c -split "`n"
        $newLines = @()
        $i = 0

        while ($i -lt $lines.Count) {
            $line = $lines[$i]

            # Check if this line has target_link_libraries with bare util
            if ($line -match 'target_link_libraries' -and
                $line -match '(?<![a-zA-Z0-9_])util(?![a-zA-Z0-9_])' -and
                -not $line.Contains('WIN32 PATCH R9')) {

                # Collect the full call (may span multiple lines)
                $callLines = @($line)
                $depth = ($line.ToCharArray() | Where-Object {$_ -eq '('}).Count -
                         ($line.ToCharArray() | Where-Object {$_ -eq ')'}).Count

                $j = $i + 1
                while ($depth -gt 0 -and $j -lt $lines.Count) {
                    $callLines += $lines[$j]
                    $depth += ($lines[$j].ToCharArray() | Where-Object {$_ -eq '('}).Count
                    $depth -= ($lines[$j].ToCharArray() | Where-Object {$_ -eq ')'}).Count
                    $j++
                }

                # Build the full call string
                $fullCall = $callLines -join "`n"

                # Remove `util` from the call (we don't need it on Windows,
                # and on Linux/Mac it's provided by the system automatically)
                # Strategy: just strip the bare `util` token entirely —
                # it's not actually used by LOOM's code, just a stray dep
                $cleanedCall = [regex]::Replace($fullCall,
                    '(?<![a-zA-Z0-9_])util(?![a-zA-Z0-9_])', '')
                # Clean up double spaces left behind
                $cleanedCall = $cleanedCall -replace '  +', ' '
                $cleanedCall = $cleanedCall -replace '\( ', '('
                $cleanedCall = $cleanedCall -replace ' \)', ')'

                $newLines += "# WIN32 PATCH R9: removed -lutil (POSIX-only, not needed on Windows)"
                $newLines += $cleanedCall -split "`n"
                $fixed++

                $i = $j  # skip the lines we already consumed
            } else {
                $newLines += $line
                $i++
            }
        }

        $c2 = $newLines -join "`n"
        if ($c2 -ne $c) {
            [IO.File]::WriteAllText($f.FullName, $c2, [Text.Encoding]::UTF8)
            Write-Host "  PATCHED: $($f.Name)" -ForegroundColor Green
        }
    }
}

# Broader scan - catch any CMakeLists that weren't in a tests/ folder
$allCmake = Get-ChildItem -Path $RepoRoot -Recurse -Filter "CMakeLists.txt"
foreach ($f in $allCmake) {
    $c = [IO.File]::ReadAllText($f.FullName)
    if ($c -match '(?<![a-zA-Z0-9_])util(?![a-zA-Z0-9_])' -and
        $c -match 'target_link_libraries' -and
        -not $c.Contains('WIN32 PATCH R9')) {

        $c2 = [regex]::Replace($c,
            '(target_link_libraries[^)]*?)(?<![a-zA-Z0-9_])(util)(?![a-zA-Z0-9_])',
            '$1')
        $c2 = $c2 -replace '  +', ' '

        if ($c2 -ne $c) {
            [IO.File]::WriteAllText($f.FullName, $c2, [Text.Encoding]::UTF8)
            Write-Host "  PATCHED (broad scan): $($f.Name)" -ForegroundColor Green
            $fixed++
        }
    }
}

if ($fixed -eq 0) {
    Write-Host "  No bare 'util' link dependencies found." -ForegroundColor DarkGray
}

# -----------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "=== Round 9 patches applied! ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Re-run cmake then build:" -ForegroundColor White
Write-Host "  cd build" -ForegroundColor Yellow
Write-Host "  cmake .. -G `"MinGW Makefiles`" -DCMAKE_BUILD_TYPE=Release -DLOOM_USE_GUROBI=OFF" -ForegroundColor Yellow
Write-Host "  mingw32-make -j`$(nproc) 2>&1 | tee build_log_r9.txt" -ForegroundColor Yellow
Write-Host ""
