# apply_patches_r5.ps1
# Round 5 patches - two remaining issues:
#   1. Polygon/wingdi clash - fix at the source in Geo.h
#   2. Agency.h _timezone member renamed by Windows timezone macro
#
# Run from the ROOT of your loom repo:
#   cd D:\path\to\loom
#   ..\loom-patches-r5\apply_patches_r5.ps1

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot  = (Get-Location).Path

Write-Host ""
Write-Host "=== LOOM Windows Patch Script - Round 5 ===" -ForegroundColor Cyan
Write-Host "Repo root : $RepoRoot"
Write-Host ""

# -----------------------------------------------------------------------
# FIX 1: Geo.h — the Polygon clash
#
# The include chain is:
#   GeoTest.cpp -> Geo.h -> [at line 1297] includes Geo.tpp
#                                            -> Misc.h -> windows.h
#                                                          -> wingdi.h (defines Polygon)
#
# By the time wingdi.h fires, the compiler is still inside Geo.h
# processing Geo.tpp. Any #undef after that point is too late for
# code that already parsed Polygon inside Geo.h's earlier sections.
#
# The ONLY reliable fix is to put the #undef Polygon INSIDE Geo.h,
# immediately after the line that includes Geo.tpp.
# That way the undef fires right after windows.h/wingdi.h are pulled
# in, before the rest of Geo.h (and any callers) see Polygon again.
# -----------------------------------------------------------------------
Write-Host "[1/2] Patching Geo.h (Polygon/wingdi clash)..." -ForegroundColor Yellow

# Find Geo.h
$geoHPath = Join-Path $RepoRoot "src\util\geo\Geo.h"
if (-not (Test-Path $geoHPath)) {
    # Try to locate it
    $found = Get-ChildItem -Path (Join-Path $RepoRoot "src") -Recurse -Filter "Geo.h" -ErrorAction SilentlyContinue
    if ($found) { $geoHPath = $found[0].FullName }
}

if (Test-Path $geoHPath) {
    $c = [IO.File]::ReadAllText($geoHPath)

    if ($c.Contains('WIN32 PATCH: undef Polygon after Geo.tpp')) {
        Write-Host "  already patched: Geo.h" -ForegroundColor DarkGray
    } else {
        # Find the #include "Geo.tpp" line (or similar .tpp include at end of file)
        $tppInclude = ($c -split "`n" | Where-Object { $_ -match '#include.*Geo\.tpp' } | Select-Object -First 1)

        $undefBlock = @"
// WIN32 PATCH: undef Polygon after Geo.tpp
// Geo.tpp includes Misc.h which includes windows.h/wingdi.h.
// wingdi.h defines Polygon() as a GDI function, clashing with
// util::geo::Polygon. We undef it here so all subsequent code
// sees only the LOOM template.
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
  #ifdef INFO
  #undef INFO
  #endif
  #ifdef WARNING
  #undef WARNING
  #endif
#endif
// END WIN32 PATCH
"@

        if ($tppInclude) {
            $c = $c.Replace($tppInclude, $tppInclude + "`n" + $undefBlock)
            [IO.File]::WriteAllText($geoHPath, $c, [Text.Encoding]::UTF8)
            Write-Host "  PATCHED: $geoHPath" -ForegroundColor Green
            Write-Host "  (inserted #undef Polygon after: $($tppInclude.Trim()))" -ForegroundColor Cyan
        } else {
            # No explicit Geo.tpp include found — append undefs at end of file
            # before any closing #endif
            $c = $c.TrimEnd() + "`n`n" + $undefBlock + "`n"
            [IO.File]::WriteAllText($geoHPath, $c, [Text.Encoding]::UTF8)
            Write-Host "  PATCHED (appended): $geoHPath" -ForegroundColor Green
        }
    }
} else {
    Write-Host "  ERROR: Geo.h not found" -ForegroundColor Red
}

# -----------------------------------------------------------------------
# FIX 2: Agency.h — _timezone member renamed by Windows macro
#
# The problem: MinGW's <time.h> defines:
#   extern long _timezone;
#   #define timezone _timezone
#
# So when the compiler sees `_timezone` as a member name in Agency.h,
# it gets preprocessed to `__timezone()` (because _timezone expands
# through the macro chain). This breaks the member initializer list.
#
# The #undef approach in R4 didn't work because the #undef in Agency.h
# fires BEFORE <time.h> is included (via the C++ standard headers
# pulled in by Writer.cpp -> fstream -> ios -> etc.)
#
# The definitive fix: rename the PARAMETER `timezone` to `tz` in
# Agency.h constructors. The MEMBER `_timezone` is fine — it only
# clashes when the parameter shadows the macro. Renaming the parameter
# breaks the macro substitution chain.
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "[2/2] Patching Agency.h (timezone parameter rename)..." -ForegroundColor Yellow

# Find Agency.h
$agencyPath = Join-Path $RepoRoot "src\cppgtfs\src\ad\cppgtfs\gtfs\Agency.h"
if (-not (Test-Path $agencyPath)) {
    $found = Get-ChildItem -Path (Join-Path $RepoRoot "src") -Recurse -Filter "Agency.h" -ErrorAction SilentlyContinue
    if ($found) { $agencyPath = $found[0].FullName }
}

if (Test-Path $agencyPath) {
    $c = [IO.File]::ReadAllText($agencyPath)

    if ($c.Contains('WIN32 PATCH: timezone->tz')) {
        Write-Host "  already patched: Agency.h" -ForegroundColor DarkGray
    } else {
        # Add a header comment marker
        $marker = "// WIN32 PATCH: timezone->tz`n"

        # Strategy: rename the constructor PARAMETER `timezone` to `tz_`
        # in both the parameter list AND the initializer list.
        # We use targeted replacements to avoid touching the member name _timezone.
        #
        # Pattern 1 (std::string constructor):
        #   const std::string& timezone  ->  const std::string& tz_
        #   _timezone(timezone)          ->  _timezone(tz_)
        #
        # Pattern 2 (const char* constructor):
        #   const char* timezone         ->  const char* tz_
        #   _timezone(timezone)          ->  _timezone(tz_)    [same replacement]

        $changed = $false

        # std::string& timezone parameter
        if ($c.Contains('const std::string& timezone')) {
            $c = $c.Replace('const std::string& timezone', 'const std::string& tz_ /* WIN32: was timezone */')
            $changed = $true
        }
        # const char* timezone parameter
        if ($c.Contains('const char* timezone')) {
            $c = $c.Replace('const char* timezone', 'const char* tz_ /* WIN32: was timezone */')
            $changed = $true
        }
        # initializer _timezone(timezone) -> _timezone(tz_)
        if ($c.Contains('_timezone(timezone)')) {
            $c = $c.Replace('_timezone(timezone)', '_timezone(tz_)')
            $changed = $true
        }

        if ($changed) {
            $c = $marker + $c
            [IO.File]::WriteAllText($agencyPath, $c, [Text.Encoding]::UTF8)
            Write-Host "  PATCHED: $agencyPath" -ForegroundColor Green
            Write-Host "  (renamed parameter 'timezone' -> 'tz_' in constructors)" -ForegroundColor Cyan
        } else {
            Write-Host "  WARNING: expected patterns not found in Agency.h" -ForegroundColor Yellow
            Write-Host "  File: $agencyPath" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "  ERROR: Agency.h not found" -ForegroundColor Red
}

# -----------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "=== Round 5 patches applied! ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Rebuild with:" -ForegroundColor White
Write-Host "  cd build" -ForegroundColor Yellow
Write-Host "  mingw32-make -j`$(nproc) 2>&1 | tee build_log_r5.txt" -ForegroundColor Yellow
Write-Host ""
Write-Host "We expect very few or zero errors this round." -ForegroundColor White
Write-Host ""
