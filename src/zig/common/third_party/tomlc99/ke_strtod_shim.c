/* Windows-only UCRT-backed strtod/strtoll for the vendored tomlc99.
 *
 * toml.c redirects strtod/strtoll here (see the guarded #defines after its
 * include block). The mingw libc Zig bundles routes strtod through gdtoa,
 * whose first call registers an atexit() cleanup into an onexit table that
 * mingw's DllMainCRTStartup never initializes in a Zig-built DLL — a write
 * into uninitialized memory that corrupts the heap (glibc tolerates it on
 * Linux; Windows' UCRT faults the next time the heap is touched). We instead
 * delegate to ucrtbase.dll's own strtod/_strtoi64, which the OS loads and
 * initializes fully, honoring the exact C endptr/base/errno contract tomlc99
 * relies on. Non-Windows builds never compile this file and keep platform
 * strtod/strtoll.
 *
 * This lives beside toml.c so a single shared tomlc99 copy serves every
 * plugin DLL that parses TOML (framework, configuration/toml); each DLL
 * compiles its own instance, giving each its own resolved function pointer. */
#ifdef _WIN32

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

static void *ucrtbase(void) {
    HMODULE h = GetModuleHandleA("ucrtbase.dll");
    if (!h)
        h = LoadLibraryA("ucrtbase.dll");
    return (void *)h;
}

double ke_toml_strtod(const char *s, char **endptr) {
    typedef double (*fn_t)(const char *, char **);
    static fn_t fn = 0;
    if (!fn)
        fn = (fn_t)GetProcAddress((HMODULE)ucrtbase(), "strtod");
    return fn(s, endptr);
}

/* The UCRT spells the 64-bit signed parse "_strtoi64"; signature and semantics
 * match strtoll exactly. */
long long ke_toml_strtoll(const char *s, char **endptr, int base) {
    typedef long long (*fn_t)(const char *, char **, int);
    static fn_t fn = 0;
    if (!fn)
        fn = (fn_t)GetProcAddress((HMODULE)ucrtbase(), "_strtoi64");
    return fn(s, endptr, base);
}

#endif /* _WIN32 */
