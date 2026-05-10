# apply_patches_r3.ps1
# Round 3 patches for LOOM Windows build
# Run from the ROOT of your loom repo:
#   cd D:\path\to\loom
#   ..\loom-patches-r3\apply_patches_r3.ps1

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot  = (Get-Location).Path

Write-Host ""
Write-Host "=== LOOM Windows Patch Script - Round 3 ===" -ForegroundColor Cyan
Write-Host "Repo root : $RepoRoot"
Write-Host ""

# -----------------------------------------------------------------------
# FIX 1: Replace win_compat.h with Round 3 version
# -----------------------------------------------------------------------
Write-Host "[1/4] Updating win_compat.h..." -ForegroundColor Yellow
Copy-Item -Path (Join-Path $ScriptDir "win_compat.h") `
          -Destination (Join-Path $RepoRoot "win_compat.h") -Force
Write-Host "  OK" -ForegroundColor Green

# -----------------------------------------------------------------------
# FIX 2: Server.cpp — also patch netinet/in.h (line after netdb.h)
#   win_compat.h already covers everything via winsock2/ws2tcpip,
#   so we just replace these includes with a single win_compat.h include.
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "[2/4] Patching src/util/http/Server.cpp (netinet/in.h, sys/socket.h etc.)..." -ForegroundColor Yellow

$serverPath = Join-Path $RepoRoot "src\util\http\Server.cpp"
if (Test-Path $serverPath) {
    $c = [IO.File]::ReadAllText($serverPath)
    $changed = $false

    # List of POSIX network headers that winsock2 covers
    $posixNetHeaders = @(
        '#include <netinet/in.h>',
        '#include <netinet/tcp.h>',
        '#include <sys/socket.h>',
        '#include <sys/types.h>',
        '#include <arpa/inet.h>',
        '#include <netdb.h>'
    )

    foreach ($hdr in $posixNetHeaders) {
        if ($c.Contains($hdr)) {
            $c = $c.Replace($hdr, "// WIN32 PATCH: $hdr covered by win_compat.h")
            Write-Host "  commented out: $hdr" -ForegroundColor Green
            $changed = $true
        }
    }

    # Make sure win_compat.h is included (it may already be from R1 patch)
    if (-not $c.Contains('win_compat.h')) {
        # Insert after first #include
        $firstInclude = ($c -split "`n" | Where-Object { $_ -match '^\s*#include' } | Select-Object -First 1)
        if ($firstInclude) {
            $c = $c.Replace($firstInclude, '#include "win_compat.h"  // WIN32 PATCH' + "`n" + $firstInclude)
            Write-Host "  inserted win_compat.h" -ForegroundColor Green
            $changed = $true
        }
    }

    if ($changed) {
        [IO.File]::WriteAllText($serverPath, $c, [Text.Encoding]::UTF8)
        Write-Host "  PATCHED: Server.cpp" -ForegroundColor Green
    } else {
        Write-Host "  no changes needed" -ForegroundColor DarkGray
    }
} else {
    Write-Host "  WARNING: Server.cpp not found" -ForegroundColor Yellow
}

# -----------------------------------------------------------------------
# FIX 3: Misc.cpp — wrap getHomeDir() with a Windows implementation.
#   The function uses: sysconf, getpwuid_r, struct passwd — all now
#   provided by win_compat.h — but the function body also uses
#   char buf[bufsize] which is a VLA (variable-length array), not
#   supported by MSVC/MinGW in some modes. We replace the entire
#   getHomeDir() function body with a clean Windows version using
#   a fixed-size buffer.
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "[3/4] Patching src/util/Misc.cpp (getHomeDir, pread, pwrite)..." -ForegroundColor Yellow

$miscPath = Join-Path $RepoRoot "src\util\Misc.cpp"
if (Test-Path $miscPath) {
    $c = [IO.File]::ReadAllText($miscPath)
    $changed = $false

    # Ensure win_compat.h is included and pwd.h/unistd.h are replaced
    foreach ($hdr in @('#include <pwd.h>', '#include <unistd.h>')) {
        if ($c.Contains($hdr)) {
            $c = $c.Replace($hdr, '#include "win_compat.h"  // WIN32 PATCH')
            Write-Host "  replaced $hdr" -ForegroundColor Green
            $changed = $true
        }
    }

    # Replace the POSIX getHomeDir implementation with a Windows one.
    # We wrap it in #ifndef _WIN32 / #else / #endif
    $oldGetHomeDir = 'std::string util::getHomeDir() {'
    $newGetHomeDir = @"
std::string util::getHomeDir() {
#ifdef _WIN32
  // WIN32 PATCH: use USERPROFILE env var
  const char* home = getenv("USERPROFILE");
  if (!home) home = getenv("HOMEPATH");
  if (!home) home = "C:\\Users\\user";
  return std::string(home);
#else
"@

    if ($c.Contains($oldGetHomeDir) -and -not $c.Contains('WIN32 PATCH: use USERPROFILE')) {
        $c = $c.Replace($oldGetHomeDir, $newGetHomeDir)
        # Now we need to close the #else block before the closing } of the function.
        # The function ends with a lone } on its own line after the return statement.
        # Find the end of getHomeDir by locating the return pwd->pw_dir pattern
        # and add #endif before the closing brace.
        $c = $c.Replace('  return std::string(pwd->pw_dir);' + "`n}", `
                         '  return std::string(pwd->pw_dir);' + "`n#endif  // WIN32 PATCH`n}")
        # fallback: simpler close if above didn't match exactly
        if (-not $c.Contains('#endif  // WIN32 PATCH')) {
            $c = $c.Replace('  return std::string(result->pw_dir);' + "`n}", `
                             '  return std::string(result->pw_dir);' + "`n#endif  // WIN32 PATCH`n}")
        }
        Write-Host "  patched getHomeDir()" -ForegroundColor Green
        $changed = $true
    } elseif ($c.Contains('WIN32 PATCH: use USERPROFILE')) {
        Write-Host "  getHomeDir already patched" -ForegroundColor DarkGray
    } else {
        Write-Host "  WARNING: getHomeDir pattern not found - may need manual patch" -ForegroundColor Yellow
    }

    if ($changed) {
        [IO.File]::WriteAllText($miscPath, $c, [Text.Encoding]::UTF8)
        Write-Host "  PATCHED: Misc.cpp" -ForegroundColor Green
    }
} else {
    Write-Host "  WARNING: Misc.cpp not found" -ForegroundColor Yellow
}

# -----------------------------------------------------------------------
# FIX 4: Polygon clash — the undef in Misc.h didn't propagate to GeoTest
#   because windows.h is included via Geo.tpp -> Misc.h, AFTER Geo.h
#   has already tried to use Polygon. The fix is to put the undef
#   directly inside Geo.h (or Geo.tpp) after its windows.h pull-in.
#   Simplest reliable fix: add the undefs at the TOP of Geo.tpp.
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "[4/4] Patching Polygon/wingdi clash in Geo.tpp and Misc.h..." -ForegroundColor Yellow

$undefBlock = @"
// WIN32 PATCH: undefine GDI names that clash with LOOM geometry types
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
// END WIN32 PATCH
"@

# Patch Geo.tpp — add undefs right after its #include of Misc.h or windows.h
$geoTppPath = Join-Path $RepoRoot "src\util\geo\Geo.tpp"
if (Test-Path $geoTppPath) {
    $c = [IO.File]::ReadAllText($geoTppPath)
    if (-not $c.Contains('WIN32 PATCH: undefine GDI')) {
        # Insert after the #include "util/Misc.h" or similar include
        $miscInclude = ($c -split "`n" | Where-Object { $_ -match 'Misc\.h' } | Select-Object -First 1)
        if ($miscInclude) {
            $c = $c.Replace($miscInclude, $miscInclude + "`n" + $undefBlock)
            [IO.File]::WriteAllText($geoTppPath, $c, [Text.Encoding]::UTF8)
            Write-Host "  PATCHED: src\util\geo\Geo.tpp" -ForegroundColor Green
        } else {
            # Just prepend to the file
            [IO.File]::WriteAllText($geoTppPath, $undefBlock + "`n" + $c, [Text.Encoding]::UTF8)
            Write-Host "  PATCHED (prepended): src\util\geo\Geo.tpp" -ForegroundColor Green
        }
    } else {
        Write-Host "  ALREADY PATCHED: Geo.tpp" -ForegroundColor DarkGray
    }
}

# Also patch Misc.h to undef after windows.h
$miscHPath = Join-Path $RepoRoot "src\util\Misc.h"
if (Test-Path $miscHPath) {
    $c = [IO.File]::ReadAllText($miscHPath)
    if (-not $c.Contains('WIN32 PATCH: undefine GDI')) {
        # Append at end of file before endif guard
        $c = $c.TrimEnd() + "`n`n" + $undefBlock + "`n"
        [IO.File]::WriteAllText($miscHPath, $c, [Text.Encoding]::UTF8)
        Write-Host "  PATCHED: src\util\Misc.h" -ForegroundColor Green
    } else {
        Write-Host "  ALREADY PATCHED: Misc.h" -ForegroundColor DarkGray
    }
}

# -----------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "=== Round 3 patches applied! ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Rebuild with:" -ForegroundColor White
Write-Host "  cd build" -ForegroundColor Yellow
Write-Host "  mingw32-make -j`$(nproc) 2>&1 | tee build_log_r3.txt" -ForegroundColor Yellow
Write-Host ""
Write-Host "Paste build_log_r3.txt to Claude if there are more errors." -ForegroundColor White
Write-Host ""
