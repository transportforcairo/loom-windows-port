# apply_patches_r10.ps1
# Round 10 - repair the main CMakeLists.txt which still has broken
# content from R8 that R9 didn't fully clean up.
#
# The error "Expected a command name, got unquoted argument with text :"
# means there is a stray generator expression fragment like:
#   $<$<NOT:$<PLATFORM_ID:Windows>>:util>
# sitting as a bare statement (not inside any command) in CMakeLists.txt.
#
# This script reads the file, shows what's around line 15, and
# removes ALL traces of R8's broken patches from ALL CMakeLists.txt files.
#
# Run from the ROOT of your loom repo:
#   cd D:\path\to\loom
#   ..\loom-patches-r10\apply_patches_r10.ps1

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot  = (Get-Location).Path

Write-Host ""
Write-Host "=== LOOM Windows Patch Script - Round 10 ===" -ForegroundColor Cyan
Write-Host "Repo root : $RepoRoot"
Write-Host ""

# -----------------------------------------------------------------------
# Show what's around line 15 of main CMakeLists.txt for diagnosis
# -----------------------------------------------------------------------
$mainCmake = Join-Path $RepoRoot "CMakeLists.txt"
$lines = [IO.File]::ReadAllLines($mainCmake)

Write-Host "Lines 10-25 of CMakeLists.txt (for diagnosis):" -ForegroundColor Cyan
for ($i = 9; $i -lt [Math]::Min(25, $lines.Count); $i++) {
    Write-Host ("  {0,3}: {1}" -f ($i+1), $lines[$i]) -ForegroundColor Gray
}
Write-Host ""

# -----------------------------------------------------------------------
# Nuclear clean: remove ALL broken R8 fragments from ALL CMakeLists.txt
# We do a full regex sweep for any line containing the broken patterns.
# -----------------------------------------------------------------------
Write-Host "Cleaning all CMakeLists.txt files of broken R8/R9 content..." -ForegroundColor Yellow

$allCmake = Get-ChildItem -Path $RepoRoot -Recurse -Filter "CMakeLists.txt" -ErrorAction SilentlyContinue
$cleaned = 0

foreach ($f in $allCmake) {
    $c = [IO.File]::ReadAllText($f.FullName)
    $c2 = $c

    # Pattern 1: bare generator expression lines (the main culprit at line 15)
    # These look like standalone lines with $< content
    $c2 = [regex]::Replace($c2,
        '(?m)^\s*\$<[^>]*>[^\n]*\n?', '')

    # Pattern 2: generator expression inside target_link_libraries
    $c2 = [regex]::Replace($c2,
        '\$<\$<NOT:\$<PLATFORM_ID:Windows>>:util>', 'util')
    $c2 = [regex]::Replace($c2,
        '\$<[^>]*:util>', 'util')

    # Pattern 3: the util stub add_library lines R8 inserted
    $c2 = [regex]::Replace($c2,
        '(?m)^\s*#\s*WIN32 PATCH R8[^\n]*\n?', '')
    $c2 = [regex]::Replace($c2,
        '(?m)^\s*add_library\s*\(\s*__util_stub\s+INTERFACE\s*\)\s*\n?', '')
    $c2 = [regex]::Replace($c2,
        '(?m)^\s*add_library\s*\(\s*util\s+ALIAS\s+__util_stub\s*\)\s*\n?', '')

    # Pattern 4: the string(REPLACE "-lutil" ...) lines R8 inserted
    $c2 = [regex]::Replace($c2,
        '(?m)^\s*string\s*\(\s*REPLACE\s+"?-lutil"?[^\n]*\n?', '')

    # Pattern 5: any leftover WIN32 PATCH R8/R9 comment lines
    $c2 = [regex]::Replace($c2,
        '(?m)^\s*#\s*WIN32 PATCH R[89][^\n]*\n?', '')

    # Pattern 6: double blank lines left behind — clean up to single blank
    $c2 = [regex]::Replace($c2, '(\r?\n){3,}', "`n`n")

    if ($c2 -ne $c) {
        [IO.File]::WriteAllText($f.FullName, $c2, [Text.Encoding]::UTF8)
        Write-Host "  CLEANED: $($f.Name)" -ForegroundColor Green
        $cleaned++
    }
}

Write-Host "  Cleaned $cleaned files." -ForegroundColor Green

# -----------------------------------------------------------------------
# Verify main CMakeLists.txt looks sane now
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "Lines 10-25 of CMakeLists.txt after repair:" -ForegroundColor Cyan
$lines2 = [IO.File]::ReadAllLines($mainCmake)
for ($i = 9; $i -lt [Math]::Min(25, $lines2.Count); $i++) {
    Write-Host ("  {0,3}: {1}" -f ($i+1), $lines2[$i]) -ForegroundColor Gray
}

# -----------------------------------------------------------------------
# Now fix -lutil the RIGHT way: directly edit the specific test
# CMakeLists.txt files that reference util, removing it cleanly.
# No generator expressions. No add_library stubs. Just delete `util`.
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "Removing bare 'util' from target_link_libraries calls..." -ForegroundColor Yellow

$testFiles = Get-ChildItem -Path $RepoRoot -Recurse -Filter "CMakeLists.txt" |
    Where-Object { $_.DirectoryName -match 'tests?' }

foreach ($f in $testFiles) {
    $c = [IO.File]::ReadAllText($f.FullName)

    # Remove bare `util` token — word boundary match
    # Only match `util` not preceded or followed by word chars (so pb_util is safe)
    if ([regex]::IsMatch($c, '(?<![a-zA-Z0-9_])util(?![a-zA-Z0-9_])')) {
        $c2 = [regex]::Replace($c,
            '(?<![a-zA-Z0-9_])util(?![a-zA-Z0-9_])', '')
        # Clean up any double spaces
        $c2 = [regex]::Replace($c2, '  +', ' ')
        $c2 = [regex]::Replace($c2, '\( ', '(')
        $c2 = [regex]::Replace($c2, ' \)', ')')

        if ($c2 -ne $c) {
            [IO.File]::WriteAllText($f.FullName, $c2, [Text.Encoding]::UTF8)
            Write-Host "  Removed util from: $($f.Name)" -ForegroundColor Green
        }
    }
}

# -----------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "=== Round 10 patches applied! ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Re-run cmake then build:" -ForegroundColor White
Write-Host "  cd build" -ForegroundColor Yellow
Write-Host "  cmake .. -G `"MinGW Makefiles`" -DCMAKE_BUILD_TYPE=Release -DLOOM_USE_GUROBI=OFF" -ForegroundColor Yellow
Write-Host "  mingw32-make -j`$(nproc) 2>&1 | tee build_log_r10.txt" -ForegroundColor Yellow
Write-Host ""
