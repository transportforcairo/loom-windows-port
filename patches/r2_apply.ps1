# apply_patches_r2.ps1
# Round 2 patches for LOOM Windows build
# Run from the ROOT of your loom repo:
#   cd D:\path\to\loom
#   ..\loom-patches-r2\apply_patches_r2.ps1

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot  = (Get-Location).Path

Write-Host ""
Write-Host "=== LOOM Windows Patch Script - Round 2 ===" -ForegroundColor Cyan
Write-Host "Repo root : $RepoRoot"
Write-Host ""

# -----------------------------------------------------------------------
# Helper
# -----------------------------------------------------------------------
function PatchFile([string]$RelPath, [string]$Old, [string]$New, [string]$Desc) {
    $full = Join-Path $RepoRoot $RelPath
    if (-not (Test-Path $full)) {
        Write-Host "  SKIP (not found): $RelPath" -ForegroundColor DarkGray
        return
    }
    $c = [IO.File]::ReadAllText($full)
    if ($c.Contains($Old)) {
        $c2 = $c.Replace($Old, $New)
        [IO.File]::WriteAllText($full, $c2, [Text.Encoding]::UTF8)
        Write-Host "  PATCHED [$Desc]: $RelPath" -ForegroundColor Green
    } elseif ($c.Contains($New.Substring(0, [Math]::Min(30, $New.Length)))) {
        Write-Host "  ALREADY PATCHED: $RelPath" -ForegroundColor DarkGray
    } else {
        Write-Host "  WARNING - pattern not found in: $RelPath" -ForegroundColor Yellow
        Write-Host "    Looking for: $($Old.Substring(0, [Math]::Min(60,$Old.Length)))" -ForegroundColor Yellow
    }
}

# -----------------------------------------------------------------------
# FIX 1: Replace win_compat.h with the updated Round 2 version
# -----------------------------------------------------------------------
Write-Host "[1/5] Updating win_compat.h (fixes usleep, netdb.h, pwd.h)..." -ForegroundColor Yellow
Copy-Item -Path (Join-Path $ScriptDir "win_compat.h") `
          -Destination (Join-Path $RepoRoot "win_compat.h") -Force
Write-Host "  OK" -ForegroundColor Green

# -----------------------------------------------------------------------
# FIX 2: Log.h — undefine Windows macros that clash with LogLevel enum
#   Windows.h defines ERROR, DEBUG, INFO, WARNING as macros.
#   The LogLevel enum uses these same names.
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "[2/5] Patching src/util/log/Log.h (ERROR/DEBUG macro clash)..." -ForegroundColor Yellow

$logPatch = @"
// WIN32 PATCH: undefine Windows macros that clash with LogLevel enum names
#ifdef ERROR
#undef ERROR
#endif
#ifdef DEBUG
#undef DEBUG
#endif
#ifdef INFO
#undef INFO
#endif
#ifdef WARNING
#undef WARNING
#endif

enum LogLevel {
"@

PatchFile "src\util\log\Log.h" "enum LogLevel {" $logPatch "undefine Windows macros"

# -----------------------------------------------------------------------
# FIX 3: Server.cpp — replace #include <netdb.h> with win_compat.h
#   netdb.h doesn't exist on Windows; winsock2/ws2tcpip cover it.
#   win_compat.h already includes those when _WIN32 is defined.
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "[3/5] Patching src/util/http/Server.cpp (netdb.h)..." -ForegroundColor Yellow
PatchFile "src\util\http\Server.cpp" `
    "#include <netdb.h>" `
    "#include ""win_compat.h""  // WIN32 PATCH: replaces netdb.h" `
    "netdb.h -> win_compat.h"

# Also patch any other includes in Server.cpp that are POSIX-only
PatchFile "src\util\http\Server.cpp" `
    "#include <unistd.h>" `
    "#include ""win_compat.h""  // WIN32 PATCH" `
    "unistd.h -> win_compat.h"

# -----------------------------------------------------------------------
# FIX 4: Misc.cpp — replace #include <pwd.h> with win_compat.h
#   pwd.h (getpwuid, getuid) doesn't exist on Windows.
#   win_compat.h provides a minimal implementation.
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "[4/5] Patching src/util/Misc.cpp (pwd.h)..." -ForegroundColor Yellow
PatchFile "src\util\Misc.cpp" `
    "#include <pwd.h>" `
    "#include ""win_compat.h""  // WIN32 PATCH: replaces pwd.h" `
    "pwd.h -> win_compat.h"

PatchFile "src\util\Misc.cpp" `
    "#include <unistd.h>" `
    "#include ""win_compat.h""  // WIN32 PATCH" `
    "unistd.h -> win_compat.h"

# -----------------------------------------------------------------------
# FIX 5: GeoTest.cpp and Polygon.h — wingdi.h defines Polygon() as a
#   Win32 GDI function, clashing with util::geo::Polygon template.
#   Fix: add #undef Polygon after windows.h is included, inside Misc.h
#   which is the file that pulls in windows.h into the geo chain.
#
#   The cleanest fix is in Misc.h (which includes windows.h) — add
#   #undef Polygon right after the windows.h include.
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "[5/5] Patching Polygon/wingdi clash..." -ForegroundColor Yellow

# Misc.h includes windows.h — add undef after it
$miscHPath = Join-Path $RepoRoot "src\util\Misc.h"
if (Test-Path $miscHPath) {
    $c = [IO.File]::ReadAllText($miscHPath)
    if (-not $c.Contains("WIN32 PATCH: undef GDI")) {
        # Find the windows.h include and add undefs after it
        $old = "#include <windows.h>"
        $new = @"
#include <windows.h>
// WIN32 PATCH: undefine GDI macros that clash with LOOM class/type names
#ifdef Polygon
#undef Polygon
#endif
#ifdef Rectangle
#undef Rectangle
#endif
#ifdef ERROR
#undef ERROR
#endif
#ifdef DEBUG  
#undef DEBUG
#endif
"@
        if ($c.Contains($old)) {
            $c2 = $c.Replace($old, $new)
            [IO.File]::WriteAllText($miscHPath, $c2, [Text.Encoding]::UTF8)
            Write-Host "  PATCHED [GDI undefs]: src\util\Misc.h" -ForegroundColor Green
        } else {
            # windows.h may be included indirectly - add the undefs at the end of Misc.h
            $appendBlock = @"

// WIN32 PATCH: undefine GDI macros that clash with LOOM class/type names
#ifdef _WIN32
  #ifdef Polygon
  #undef Polygon
  #endif
  #ifdef Rectangle
  #undef Rectangle
  #endif
  #ifdef ERROR
  #undef ERROR
  #endif
  #ifdef DEBUG
  #undef DEBUG
  #endif
#endif
"@
            $c2 = $c + $appendBlock
            [IO.File]::WriteAllText($miscHPath, $c2, [Text.Encoding]::UTF8)
            Write-Host "  PATCHED [GDI undefs appended]: src\util\Misc.h" -ForegroundColor Green
        }
    } else {
        Write-Host "  ALREADY PATCHED: src\util\Misc.h" -ForegroundColor DarkGray
    }
} else {
    Write-Host "  WARNING: src\util\Misc.h not found" -ForegroundColor Yellow
}

# Also add the undef directly in win_compat.h at the end of the _WIN32 block
# (already included in the new win_compat.h above via NOMINMAX/WIN32_LEAN_AND_MEAN)

# -----------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "=== Round 2 patches applied! ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Now rebuild:" -ForegroundColor White
Write-Host ""
Write-Host "  cd build" -ForegroundColor Yellow
Write-Host "  mingw32-make -j`$(nproc) 2>&1 | tee build_log_r2.txt" -ForegroundColor Yellow
Write-Host ""
Write-Host "Paste build_log_r2.txt to Claude if there are more errors." -ForegroundColor White
Write-Host ""
