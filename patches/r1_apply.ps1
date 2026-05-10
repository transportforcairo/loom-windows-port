# apply_patches.ps1  v2
# Run from the ROOT of your cloned loom repo in PowerShell:
#   cd D:\path\to\loom
#   ..\loom-patches\apply_patches.ps1

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot  = (Get-Location).Path

Write-Host ""
Write-Host "=== LOOM Windows Patch Script (PowerShell v2) ===" -ForegroundColor Cyan
Write-Host "Repo root : $RepoRoot"
Write-Host "Patch dir : $ScriptDir"
Write-Host ""

# -----------------------------------------------------------------------
# Helper: safe in-place text replacement avoiding multi-argument -replace
# -----------------------------------------------------------------------
function PatchFile {
    param([string]$Path, [string]$Old, [string]$New)
    $c = [System.IO.File]::ReadAllText($Path)
    $c2 = $c.Replace($Old, $New)
    if ($c2 -ne $c) {
        [System.IO.File]::WriteAllText($Path, $c2, [System.Text.Encoding]::UTF8)
        return $true
    }
    return $false
}

# -----------------------------------------------------------------------
# Step 1: Copy win_compat.h into repo root
# -----------------------------------------------------------------------
Write-Host "[1/3] Copying win_compat.h to repo root..." -ForegroundColor Yellow
Copy-Item -Path (Join-Path $ScriptDir "win_compat.h") `
          -Destination (Join-Path $RepoRoot "win_compat.h") -Force
Write-Host "      OK" -ForegroundColor Green

# -----------------------------------------------------------------------
# Step 2: Patch all *Main.cpp files
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "[2/3] Patching *Main.cpp files..." -ForegroundColor Yellow

$mainFiles = Get-ChildItem -Path (Join-Path $RepoRoot "src") -Recurse -Filter "*Main.cpp"

if ($mainFiles.Count -eq 0) {
    Write-Host "      WARNING: No *Main.cpp files found under src/" -ForegroundColor Red
} else {
    foreach ($f in $mainFiles) {
        Write-Host "      $($f.Name)"
        $content = [System.IO.File]::ReadAllText($f.FullName)

        $changed = $false

        # Replace #include <unistd.h>
        if ($content.Contains('#include <unistd.h>')) {
            $content = $content.Replace('#include <unistd.h>', '#include "win_compat.h"  // WIN32 PATCH')
            Write-Host "        - replaced <unistd.h>" -ForegroundColor Green
            $changed = $true
        }

        # Insert win_compat.h if not present at all
        if (-not $content.Contains('win_compat.h')) {
            # Insert after the first #include line
            $firstInclude = ($content -split "`n" | Where-Object { $_ -match '^\s*#include' } | Select-Object -First 1)
            if ($firstInclude) {
                $content = $content.Replace($firstInclude, $firstInclude + "`n#include " + '"win_compat.h"  // WIN32 PATCH')
                Write-Host "        - inserted win_compat.h" -ForegroundColor Green
                $changed = $true
            }
        }

        # Insert win_set_binary_stdio() as first line of main()
        if (-not $content.Contains('win_set_binary_stdio')) {
            # Find "int main(" and the opening brace on same or next line
            # Strategy: look for common patterns
            $patterns = @(
                "int main(int argc, char** argv) {",
                "int main(int argc, char* argv[]) {",
                "int main(int argc, char **argv) {",
                "int main() {"
            )
            foreach ($p in $patterns) {
                if ($content.Contains($p)) {
                    $content = $content.Replace($p, $p + "`n  win_set_binary_stdio();  // WIN32 PATCH")
                    Write-Host "        - added win_set_binary_stdio()" -ForegroundColor Green
                    $changed = $true
                    break
                }
            }
        }

        if ($changed) {
            [System.IO.File]::WriteAllText($f.FullName, $content, [System.Text.Encoding]::UTF8)
        } else {
            Write-Host "        - no changes needed" -ForegroundColor DarkGray
        }
    }
}
Write-Host "      Done." -ForegroundColor Green

# -----------------------------------------------------------------------
# Step 3: Patch CMakeLists.txt
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "[3/3] Patching CMakeLists.txt..." -ForegroundColor Yellow

$cmakeFile = Join-Path $RepoRoot "CMakeLists.txt"
$cmake = [System.IO.File]::ReadAllText($cmakeFile)

if ($cmake.Contains('WIN32 PATCH')) {
    Write-Host "      Already patched, skipping." -ForegroundColor DarkGray
} else {
    $win32Block = @"


# ==== BEGIN WIN32 PATCH ====
if(WIN32)
  message(STATUS "WIN32 build -- applying Windows compatibility settings")
  include_directories(`${CMAKE_SOURCE_DIR})
  add_compile_definitions(NOMINMAX WIN32_LEAN_AND_MEAN)
  set(CMAKE_CXX_STANDARD 17)
  set(CMAKE_CXX_STANDARD_REQUIRED ON)
  link_libraries(ws2_32 winmm)
  add_compile_options(-Wno-deprecated-declarations)
endif()
# ==== END WIN32 PATCH ====

"@

    # Find end of project() line and insert after it
    $projectLine = ($cmake -split "`n" | Where-Object { $_ -match '^\s*project\s*\(' } | Select-Object -First 1)
    if ($projectLine) {
        $cmake = $cmake.Replace($projectLine, $projectLine + $win32Block)
        [System.IO.File]::WriteAllText($cmakeFile, $cmake, [System.Text.Encoding]::UTF8)
        Write-Host "      WIN32 block inserted." -ForegroundColor Green
    } else {
        Write-Host "      WARNING: could not find project() line." -ForegroundColor Red
    }
}

# -----------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "=== Patch complete! ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps - open MSYS2 MinGW64 shell and run:" -ForegroundColor White
Write-Host ""
Write-Host "  cd /d/path/to/loom" -ForegroundColor Yellow
Write-Host "  mkdir build && cd build" -ForegroundColor Yellow
Write-Host "  cmake .. -G `"MinGW Makefiles`" -DCMAKE_BUILD_TYPE=Release -DLOOM_USE_GUROBI=OFF" -ForegroundColor Yellow
Write-Host "  mingw32-make -j`$(nproc) 2>&1 | tee build_log.txt" -ForegroundColor Yellow
Write-Host ""
Write-Host "Paste build_log.txt to Claude for Round 2 patches." -ForegroundColor White
Write-Host ""
