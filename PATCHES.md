# Windows Compatibility Patches

This document is a full registry of every source-level change made to the upstream
[LOOM](https://github.com/ad-freiburg/loom) repository to enable building and running
on Windows (MSYS2 UCRT64).

All changes are Windows compatibility shims only. No modifications were made to
LOOM's core algorithms, data structures, or output behaviour.

Produced by [Transport for Cairo](https://transportforcairo.com), 2026.

---

## New Files

| File | Purpose |
|------|---------|
| `win_compat.h` | Core POSIX compatibility shim. Placed in repo root. Provides Windows equivalents for `unistd.h`, `dirent.h`, `pwd.h`, `isatty`, `getpid`, `ssize_t`, `uid_t`, `getpwuid`/`getpwuid_r`, `sysconf`, `pread`/`pwrite`, and binary stdio initialisation. Includes `winsock2.h`/`ws2tcpip.h` in place of `netdb.h`/`netinet/in.h`. MSYS2 UCRT64-aware: includes the system `unistd.h` first to avoid conflicts. |

---

## Modified Files

### Build System

| File | Change |
|------|--------|
| `CMakeLists.txt` | Added `if(WIN32)` block: sets C++17 standard, adds `NOMINMAX`, `WIN32_LEAN_AND_MEAN`, `NOGDI`, `NOUSER`, `NOSOUND` as global compile definitions, links `ws2_32` and `winmm`, adds repo root to include path. |
| `src/dot/tests/CMakeLists.txt` | Removed `-lutil` link dependency (POSIX-only library, not available on Windows, not used by LOOM code). |
| `src/gtfs2graph/tests/CMakeLists.txt` | Same as above. |
| `src/octi/tests/CMakeLists.txt` | Same as above. |

---

### Entry Points

All `*Main.cpp` files received two changes:
1. `#include <unistd.h>` replaced with `#include "win_compat.h"`
2. `win_set_binary_stdio()` added as the first statement in `main()` — prevents Windows from corrupting piped GeoJSON data with `\r\n` translation.

Affected files:
- `src/loom/LoomMain.cpp`
- `src/topo/TopoMain.cpp`
- `src/octi/OctiMain.cpp`
- `src/gtfs2graph/Gtfs2GraphMain.cpp`
- `src/dot/Dot2TgMain.cpp`
- `src/topoeval/TopoEvalMain.cpp`
- `src/transitmap/TransitMapMain.cpp`

---

### Utility Library (`src/util/`)

| File | Change |
|------|--------|
| `src/util/Misc.h` | Added `#define NOGDI` before `#include <windows.h>` — prevents `wingdi.h` from loading, which defines `Polygon()` and `Rectangle()` as GDI functions that clash with `util::geo::Polygon` and `util::geo::Rectangle`. |
| `src/util/Misc.cpp` | Replaced `#include <pwd.h>` and `#include <unistd.h>` with `win_compat.h`. Wrapped `getHomeDir()` with `#ifdef _WIN32` to use `USERPROFILE` environment variable instead of `getpwuid_r`. |
| `src/util/log/Log.h` | Added `#undef ERROR`, `#undef DEBUG`, `#undef INFO`, `#undef WARNING` before the `LogLevel` enum — `windows.h` defines these as macros which conflict with the enum member names. |
| `src/util/geo/Geo.h` | Added `#undef Polygon`, `#undef Rectangle`, and related GDI macro undefs immediately after `#include "Geo.tpp"` — the `.tpp` file pulls in `Misc.h` → `windows.h` → `wingdi.h`, so the undefs must follow the include. |
| `src/util/http/Server.cpp` | Replaced POSIX network headers (`netdb.h`, `netinet/in.h`, `sys/socket.h`, `arpa/inet.h`) with `win_compat.h` (which provides `winsock2.h`/`ws2tcpip.h`). Added `(const char*)` cast on `setsockopt` optval parameter (Winsock requires `const char*`, POSIX uses `const void*`). Replaced `SO_REUSEPORT` with `SO_REUSEADDR` (not available on Windows). Guarded `signal(SIGPIPE, SIG_IGN)` with `#ifndef _WIN32`. Defined `MSG_NOSIGNAL = 0` (no-op on Windows where `send()` never raises SIGPIPE). |
| `src/util/protobuf/Protobuf.h` | Guarded `#include <arpa/inet.h>` with `#ifdef _WIN32` / `#include <winsock2.h>` / `#else` / `#endif`. |

---

### cppgtfs Submodule (`src/cppgtfs/`)

The `timezone` identifier conflict is the most pervasive issue in this submodule.
MinGW's `<time.h>` defines `#define timezone _timezone`, which causes the preprocessor
to transform any identifier named `_timezone` or used as a parameter named `timezone`
into a broken expansion.

| File | Change |
|------|--------|
| `src/cppgtfs/src/ad/cppgtfs/gtfs/Agency.h` | Renamed constructor parameter `timezone` → `tz_` in all constructors. Renamed member `_timezone` → `_tz` throughout (declaration, initialiser lists, getters, setters). |
| `src/cppgtfs/src/ad/cppgtfs/Parser.tpp` | Renamed internal struct field `stop_timezone` → `stop_tz` (C++ identifier). **Restored** CSV column lookup strings `"agency_timezone"` and `"stop_timezone"` to their original values — these are GTFS specification column names and must not be renamed. |
| `src/cppgtfs/src/ad/cppgtfs/Writer.cpp` | Same: renamed C++ identifiers, restored GTFS CSV header strings `"agency_timezone"` and `"stop_timezone"`. |
| All other cppgtfs `.h`/`.cpp`/`.tpp` files | Bulk rename of `_timezone` → `_tz` and `stop_timezone` → `stop_tz` as C++ identifiers where referenced. |

---

### Transit Map Output (`src/transitmap/`)

| File | Change |
|------|--------|
| `src/transitmap/output/MvtRenderer.cpp` | Added `#include <direct.h>` (provides `mkdir` on Windows). Changed `mkdir(path, S_IRWXU \| S_IRWXG \| S_IROTH \| S_IXOTH)` to `mkdir(path)` — Windows `mkdir` takes only one argument (no permission bits). |

---

## Key Principles Applied

1. **Never rename GTFS string literals.** Column names like `"agency_timezone"` and `"stop_timezone"` are part of the GTFS specification. Only C++ identifiers were renamed.

2. **NOGDI over #undef.** Defining `NOGDI` before `windows.h` prevents `wingdi.h` from loading entirely, which is cleaner than trying to `#undef` individual macros after the fact. LOOM uses no GDI functions.

3. **Work with MSYS2's headers, not against them.** MSYS2 UCRT64 ships its own `unistd.h`, `sleep()`, and other POSIX stubs. Our shim includes the system header first, then only adds what's genuinely missing (`uid_t`, `getpwuid`, `pread`/`pwrite`).

4. **No algorithmic changes.** Every patch in this registry is a header substitution, a cast, a preprocessor guard, or a rename. Zero changes to LOOM's optimisation logic, graph algorithms, or rendering code.

---

## Building from Source

See [README.md](README.md) for full build instructions.

Patch scripts (PowerShell) for applying these changes to a fresh clone are available
in the `patches/` directory.
