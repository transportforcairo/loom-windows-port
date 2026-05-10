// win_compat.h  (Round 4)
// Windows compatibility shim for LOOM - MSYS2 UCRT64 aware.
// Place in repo root (same folder as CMakeLists.txt).

#ifndef WIN_COMPAT_H
#define WIN_COMPAT_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32

// -----------------------------------------------------------------------
// Windows + Winsock headers (order matters — winsock2 before windows.h)
// -----------------------------------------------------------------------
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
// WIN32 PATCH R6: NOGDI prevents wingdi.h (Polygon clash)
#ifndef NOGDI
#define NOGDI
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <io.h>
#include <fcntl.h>
#include <process.h>

// -----------------------------------------------------------------------
// MSYS2 UCRT64 ships unistd.h — include it so we don't conflict with it
// -----------------------------------------------------------------------
#include <unistd.h>

// -----------------------------------------------------------------------
// Undefine GDI/WinBase macros that clash with LOOM names.
// Must happen AFTER windows.h.
// -----------------------------------------------------------------------
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

// -----------------------------------------------------------------------
// ssize_t
// -----------------------------------------------------------------------
#ifndef _SSIZE_T_DEFINED
#define _SSIZE_T_DEFINED
#ifdef _WIN64
  typedef __int64 ssize_t;
#else
  typedef int ssize_t;
#endif
#endif

// -----------------------------------------------------------------------
// uid_t — not in MSYS2 UCRT64 unistd.h
// -----------------------------------------------------------------------
#ifndef _UID_T_DEFINED
#define _UID_T_DEFINED
typedef unsigned int uid_t;
#endif

// -----------------------------------------------------------------------
// passwd + getpwuid + getpwuid_r + getuid + sysconf
// -----------------------------------------------------------------------
#ifndef _PASSWD_DEFINED
#define _PASSWD_DEFINED
struct passwd {
    char* pw_name;
    char* pw_dir;
    char* pw_shell;
};
#endif

#ifndef _GETUID_DEFINED
#define _GETUID_DEFINED
static inline uid_t getuid(void) { return 0; }
#endif

#ifndef _GETPWUID_DEFINED
#define _GETPWUID_DEFINED
static inline struct passwd* getpwuid(uid_t uid) {
    (void)uid;
    static struct passwd pw;
    static char name[256];
    static char dir[MAX_PATH];
    DWORD sz = 256;
    GetUserNameA(name, &sz);
    pw.pw_name = name;
    const char* home = getenv("USERPROFILE");
    if (!home) home = getenv("HOMEPATH");
    if (!home) home = "C:\\Users\\user";
    strncpy(dir, home, MAX_PATH - 1);
    dir[MAX_PATH - 1] = '\0';
    pw.pw_dir = dir;
    pw.pw_shell = (char*)"";
    return &pw;
}
#endif

#ifndef _GETPWUID_R_DEFINED
#define _GETPWUID_R_DEFINED
static inline int getpwuid_r(uid_t uid, struct passwd* pwd,
                              char* buf, size_t buflen,
                              struct passwd** result) {
    (void)buf; (void)buflen;
    struct passwd* p = getpwuid(uid);
    if (p) { *pwd = *p; *result = pwd; return 0; }
    *result = NULL;
    return -1;
}
#endif

#ifndef _SC_GETPW_R_SIZE_MAX
#define _SC_GETPW_R_SIZE_MAX 0
#endif
#ifndef _SYSCONF_DEFINED
#define _SYSCONF_DEFINED
static inline long sysconf(int name) { (void)name; return 1024; }
#endif

// -----------------------------------------------------------------------
// pread / pwrite — positional I/O via OVERLAPPED
// Use memset to silence missing-initializer warnings on OVERLAPPED.
// -----------------------------------------------------------------------
#ifndef _PREAD_DEFINED
#define _PREAD_DEFINED
static inline ssize_t pread(int fd, void* buf, size_t count, size_t offset) {
    HANDLE h = (HANDLE)_get_osfhandle(fd);
    if (h == INVALID_HANDLE_VALUE) return -1;
    OVERLAPPED ov;
    memset(&ov, 0, sizeof(ov));
    ov.Offset     = (DWORD)(offset & 0xFFFFFFFF);
    ov.OffsetHigh = (DWORD)(offset >> 32);
    DWORD bytesRead = 0;
    if (!ReadFile(h, buf, (DWORD)count, &bytesRead, &ov)) return -1;
    return (ssize_t)bytesRead;
}
#endif

#ifndef _PWRITE_DEFINED
#define _PWRITE_DEFINED
static inline ssize_t pwrite(int fd, const void* buf, size_t count, size_t offset) {
    HANDLE h = (HANDLE)_get_osfhandle(fd);
    if (h == INVALID_HANDLE_VALUE) return -1;
    OVERLAPPED ov;
    memset(&ov, 0, sizeof(ov));
    ov.Offset     = (DWORD)(offset & 0xFFFFFFFF);
    ov.OffsetHigh = (DWORD)(offset >> 32);
    DWORD bytesWritten = 0;
    if (!WriteFile(h, buf, (DWORD)count, &bytesWritten, &ov)) return -1;
    return (ssize_t)bytesWritten;
}
#endif

// -----------------------------------------------------------------------
// dirent.h
// -----------------------------------------------------------------------
#ifndef _DIRENT_DEFINED
#define _DIRENT_DEFINED
struct dirent {
    char d_name[MAX_PATH];
};
typedef struct {
    HANDLE           handle;
    WIN32_FIND_DATAA findData;
    struct dirent    entry;
    int              firstRead;
} DIR;

static inline DIR* opendir(const char* path) {
    char search[MAX_PATH];
    snprintf(search, MAX_PATH, "%s\\*", path);
    DIR* d = (DIR*)malloc(sizeof(DIR));
    if (!d) return NULL;
    d->handle = FindFirstFileA(search, &d->findData);
    if (d->handle == INVALID_HANDLE_VALUE) { free(d); return NULL; }
    d->firstRead = 1;
    return d;
}
static inline struct dirent* readdir(DIR* d) {
    if (!d) return NULL;
    if (d->firstRead) { d->firstRead = 0; }
    else if (!FindNextFileA(d->handle, &d->findData)) return NULL;
    strncpy(d->entry.d_name, d->findData.cFileName, MAX_PATH - 1);
    d->entry.d_name[MAX_PATH - 1] = '\0';
    return &d->entry;
}
static inline int closedir(DIR* d) {
    if (!d) return -1;
    FindClose(d->handle);
    free(d);
    return 0;
}
#endif

// -----------------------------------------------------------------------
// Binary stdio
// -----------------------------------------------------------------------
static inline void win_set_binary_stdio(void) {
    _setmode(_fileno(stdin),  _O_BINARY);
    _setmode(_fileno(stdout), _O_BINARY);
}

#else
#include <unistd.h>
#include <dirent.h>
#include <netdb.h>
#include <netinet/in.h>
#include <pwd.h>
#include <sys/types.h>
static inline void win_set_binary_stdio(void) {}
#endif  // _WIN32

#endif  // WIN_COMPAT_H
