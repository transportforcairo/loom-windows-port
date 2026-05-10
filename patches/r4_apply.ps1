# apply_patches_r4.ps1
# Round 4 patches for LOOM Windows build
# Run from the ROOT of your loom repo:
#   cd D:\path\to\loom
#   ..\loom-patches-r4\apply_patches_r4.ps1

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot  = (Get-Location).Path

Write-Host ""
Write-Host "=== LOOM Windows Patch Script - Round 4 ===" -ForegroundColor Cyan
Write-Host "Repo root : $RepoRoot"
Write-Host ""

# -----------------------------------------------------------------------
# FIX 1: Replace win_compat.h
# -----------------------------------------------------------------------
Write-Host "[1/5] Updating win_compat.h..." -ForegroundColor Yellow
Copy-Item -Path (Join-Path $ScriptDir "win_compat.h") `
          -Destination (Join-Path $RepoRoot "win_compat.h") -Force
Write-Host "  OK" -ForegroundColor Green

# -----------------------------------------------------------------------
# FIX 2: Misc.cpp — getHomeDir() has an unterminated #else.
#   The R3 patch inserted #ifdef _WIN32 / return home; but never closed
#   the #else block. We need to rewrite the entire getHomeDir() function
#   with a clean conditional.
#   Strategy: replace everything from "std::string util::getHomeDir() {"
#   to the next lone "}" with our Windows-aware version.
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "[2/5] Fixing Misc.cpp getHomeDir() (unterminated #else)..." -ForegroundColor Yellow

$miscPath = Join-Path $RepoRoot "src\util\Misc.cpp"
if (Test-Path $miscPath) {
    $c = [IO.File]::ReadAllText($miscPath)

    # Remove any partial WIN32 PATCH that was applied in R3
    # by stripping from the function start to end of function
    # and replacing with a clean version.

    # The clean replacement for the entire getHomeDir function body:
    $cleanFunc = @"
std::string util::getHomeDir() {
#ifdef _WIN32
  // WIN32 PATCH: use environment variable
  const char* home = getenv("USERPROFILE");
  if (!home) home = getenv("HOMEPATH");
  if (!home) home = "C:\\Users\\user";
  return std::string(home);
#else
  struct passwd pwd;
  struct passwd* result;
  long bufsize = sysconf(_SC_GETPW_R_SIZE_MAX);
  if (bufsize <= 0) bufsize = 1024;
  std::vector<char> buf(bufsize);
  getpwuid_r(getuid(), &pwd, buf.data(), bufsize, &result);
  if (result) return std::string(result->pw_dir);
  return "";
#endif
}
"@

    # Find the function — it may have various forms after R3 partial patching.
    # Use a regex-style approach: find the function start and replace to next
    # top-level closing brace.
    # Simpler: find the marker we know is there and replace the whole block.

    # Pattern 1: if R3 left an unterminated #else (our fault)
    # Pattern 2: if it's still the original POSIX version
    # We'll handle both by finding "std::string util::getHomeDir() {"
    # and replacing everything up to and including the matching closing "}"

    $funcStart = 'std::string util::getHomeDir() {'
    $idx = $c.IndexOf($funcStart)

    if ($idx -ge 0) {
        # Find the matching closing brace by counting braces
        $depth = 0
        $start = $idx
        $end = -1
        for ($i = $idx; $i -lt $c.Length; $i++) {
            if ($c[$i] -eq '{') { $depth++ }
            elseif ($c[$i] -eq '}') {
                $depth--
                if ($depth -eq 0) { $end = $i; break }
            }
        }

        if ($end -ge 0) {
            $before = $c.Substring(0, $start)
            $after  = $c.Substring($end + 1)
            $c2 = $before + $cleanFunc + $after
            [IO.File]::WriteAllText($miscPath, $c2, [Text.Encoding]::UTF8)
            Write-Host "  PATCHED: getHomeDir() replaced cleanly" -ForegroundColor Green
        } else {
            Write-Host "  WARNING: could not find closing brace of getHomeDir()" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  WARNING: getHomeDir() not found in Misc.cpp" -ForegroundColor Yellow
    }
} else {
    Write-Host "  WARNING: Misc.cpp not found" -ForegroundColor Yellow
}

# -----------------------------------------------------------------------
# FIX 3: Server.cpp
#   (a) setsockopt needs cast: &y -> (const char*)&y   (Winsock vs POSIX)
#   (b) SO_REUSEPORT doesn't exist on Windows -> replace with SO_REUSEADDR
#   (c) SIGPIPE doesn't exist on Windows -> guard with #ifndef
#   (d) MSG_NOSIGNAL doesn't exist on Windows -> define as 0
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "[3/5] Patching src/util/http/Server.cpp (setsockopt, SO_REUSEPORT, SIGPIPE, MSG_NOSIGNAL)..." -ForegroundColor Yellow

$serverPath = Join-Path $RepoRoot "src\util\http\Server.cpp"
if (Test-Path $serverPath) {
    $c = [IO.File]::ReadAllText($serverPath)
    $changed = $false

    # (a) setsockopt cast: &y -> (const char*)&y
    # Winsock requires const char* for optval, POSIX uses const void*
    if ($c.Contains('setsockopt(_sock, SOL_SOCKET, SO_REUSEADDR, &y,') -and
        -not $c.Contains('(const char*)&y')) {
        $c = $c.Replace(
            'setsockopt(_sock, SOL_SOCKET, SO_REUSEADDR, &y,',
            'setsockopt(_sock, SOL_SOCKET, SO_REUSEADDR, (const char*)&y,')
        Write-Host "  fixed setsockopt cast (SO_REUSEADDR)" -ForegroundColor Green
        $changed = $true
    }

    # (b) SO_REUSEPORT -> SO_REUSEADDR on Windows (Windows has no REUSEPORT)
    if ($c.Contains('SO_REUSEPORT')) {
        $c = $c.Replace(
            'setsockopt(_sock, SOL_SOCKET, SO_REUSEPORT, &y,',
            'setsockopt(_sock, SOL_SOCKET, SO_REUSEADDR, (const char*)&y,')
        # In case it doesn't have &y pattern:
        $c = $c.Replace('SO_REUSEPORT', 'SO_REUSEADDR  /* WIN32: no REUSEPORT */')
        Write-Host "  replaced SO_REUSEPORT with SO_REUSEADDR" -ForegroundColor Green
        $changed = $true
    }

    # (c) SIGPIPE — wrap with #ifndef _WIN32
    if ($c.Contains('signal(SIGPIPE, SIG_IGN)') -and -not $c.Contains('#ifndef _WIN32')) {
        $c = $c.Replace(
            'signal(SIGPIPE, SIG_IGN);',
            '#ifndef _WIN32  // WIN32 PATCH: no SIGPIPE on Windows' + "`n" +
            '  signal(SIGPIPE, SIG_IGN);' + "`n" +
            '#endif')
        Write-Host "  guarded SIGPIPE with #ifndef _WIN32" -ForegroundColor Green
        $changed = $true
    }

    # (d) MSG_NOSIGNAL — define as 0 if not present; add near top of file
    if ($c.Contains('MSG_NOSIGNAL') -and -not $c.Contains('#define MSG_NOSIGNAL')) {
        $insert = @"
// WIN32 PATCH: MSG_NOSIGNAL not defined on Windows; use 0 (no-op flag)
#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0
#endif

"@
        # Insert after win_compat.h include or after first #include
        if ($c.Contains('#include "win_compat.h"')) {
            $c = $c.Replace('#include "win_compat.h"  // WIN32 PATCH: replaces netdb.h',
                            '#include "win_compat.h"  // WIN32 PATCH: replaces netdb.h' + "`n" + $insert)
        } else {
            $firstInc = ($c -split "`n" | Where-Object { $_ -match '^\s*#include' } | Select-Object -First 1)
            $c = $c.Replace($firstInc, $firstInc + "`n" + $insert)
        }
        Write-Host "  defined MSG_NOSIGNAL = 0" -ForegroundColor Green
        $changed = $true
    }

    if ($changed) {
        [IO.File]::WriteAllText($serverPath, $c, [Text.Encoding]::UTF8)
        Write-Host "  PATCHED: Server.cpp" -ForegroundColor Green
    } else {
        Write-Host "  no new changes needed" -ForegroundColor DarkGray
    }
} else {
    Write-Host "  WARNING: Server.cpp not found" -ForegroundColor Yellow
}

# -----------------------------------------------------------------------
# FIX 4: Agency.h — `timezone` member name clash.
#   On Windows/MinGW, `timezone` is a global variable declared in
#   <time.h> (as `long _timezone` and aliased as `timezone`).
#   The Agency class has a member `_timezone` but the constructor
#   parameter is named `timezone`, which collides.
#   Fix: rename the constructor parameter `timezone` -> `tz` throughout
#   Agency.h.
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "[4/5] Patching Agency.h (timezone parameter name clash)..." -ForegroundColor Yellow

$agencyPath = Join-Path $RepoRoot "src\cppgtfs\src\ad\cppgtfs\gtfs\Agency.h"
if (Test-Path $agencyPath) {
    $c = [IO.File]::ReadAllText($agencyPath)

    if ($c.Contains('const std::string& timezone') -and -not $c.Contains('WIN32 PATCH')) {
        # Add the undef at the top of the file, after #pragma once or first include
        $undef = @"
// WIN32 PATCH: `timezone` is a global in MinGW's time.h; undef it
#ifdef _WIN32
#ifdef timezone
#undef timezone
#endif
#endif

"@
        # Find first #include or #pragma
        $firstLine = ($c -split "`n" | Where-Object { $_ -match '^\s*#(include|pragma)' } | Select-Object -First 1)
        if ($firstLine) {
            $c = $c.Replace($firstLine, $undef + $firstLine)
        }

        [IO.File]::WriteAllText($agencyPath, $c, [Text.Encoding]::UTF8)
        Write-Host "  PATCHED: Agency.h (undef timezone)" -ForegroundColor Green
    } else {
        Write-Host "  already patched or pattern not found" -ForegroundColor DarkGray
    }
} else {
    Write-Host "  WARNING: Agency.h not found at expected path" -ForegroundColor Yellow
    # Try to find it
    $found = Get-ChildItem -Path $RepoRoot -Recurse -Filter "Agency.h" -ErrorAction SilentlyContinue
    foreach ($f in $found) { Write-Host "  Found at: $($f.FullName)" -ForegroundColor Cyan }
}

# -----------------------------------------------------------------------
# FIX 5: Polygon clash — still persisting in GeoTest.cpp.
#   The undef in Geo.tpp/Misc.h isn't working because GeoTest.cpp
#   includes Geo.h which pulls in Geo.tpp which pulls in Misc.h which
#   pulls in windows.h, and the undef happens AFTER GeoTest.cpp has
#   already seen Polygon from Geo.h's earlier includes.
#
#   The definitive fix: put #undef Polygon directly in Polygon.h,
#   at the very end of the file, so it's always undefined after
#   anyone includes Polygon.h — regardless of include order.
#
#   Wait — that would break the class definition itself. Instead,
#   add the undef to GeoTest.cpp directly, before any use of Polygon.
#   And also add it to Collection.h which is the file that exposes
#   Polygon to the world.
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "[5/5] Fixing Polygon/wingdi clash (GeoTest.cpp and Collection.h)..." -ForegroundColor Yellow

$undefPolygon = @"
// WIN32 PATCH: wingdi.h defines Polygon() as a GDI function.
// Undefine it here so util::geo::Polygon template is unambiguous.
#ifdef _WIN32
#ifdef Polygon
#undef Polygon
#endif
#ifdef Rectangle
#undef Rectangle
#endif
#endif
// END WIN32 PATCH

"@

# Patch Collection.h — it's the header that brings Polygon into scope
$collectionPath = Join-Path $RepoRoot "src\util\geo\Collection.h"
if (Test-Path $collectionPath) {
    $c = [IO.File]::ReadAllText($collectionPath)
    if (-not $c.Contains('WIN32 PATCH: wingdi')) {
        $c = $c.TrimEnd() + "`n`n" + $undefPolygon
        [IO.File]::WriteAllText($collectionPath, $c, [Text.Encoding]::UTF8)
        Write-Host "  PATCHED: src\util\geo\Collection.h" -ForegroundColor Green
    } else {
        Write-Host "  already patched: Collection.h" -ForegroundColor DarkGray
    }
}

# Patch GeoTest.cpp — add undef right after its includes
$geoTestPath = Join-Path $RepoRoot "src\util\tests\GeoTest.cpp"
if (Test-Path $geoTestPath) {
    $c = [IO.File]::ReadAllText($geoTestPath)
    if (-not $c.Contains('WIN32 PATCH: wingdi')) {
        # Insert after the last #include at the top of the file
        $lines = $c -split "`n"
        $lastIncludeIdx = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*#include') { $lastIncludeIdx = $i }
            elseif ($lastIncludeIdx -ge 0 -and $lines[$i] -notmatch '^\s*#') { break }
        }
        if ($lastIncludeIdx -ge 0) {
            $lines[$lastIncludeIdx] = $lines[$lastIncludeIdx] + "`n" + $undefPolygon
            $c2 = $lines -join "`n"
            [IO.File]::WriteAllText($geoTestPath, $c2, [Text.Encoding]::UTF8)
            Write-Host "  PATCHED: src\util\tests\GeoTest.cpp" -ForegroundColor Green
        }
    } else {
        Write-Host "  already patched: GeoTest.cpp" -ForegroundColor DarkGray
    }
}

# -----------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "=== Round 4 patches applied! ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Rebuild with:" -ForegroundColor White
Write-Host "  cd build" -ForegroundColor Yellow
Write-Host "  mingw32-make -j`$(nproc) 2>&1 | tee build_log_r4.txt" -ForegroundColor Yellow
Write-Host ""
Write-Host "Paste build_log_r4.txt to Claude if there are more errors." -ForegroundColor White
Write-Host ""
