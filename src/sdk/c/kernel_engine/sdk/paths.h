#ifndef KERNEL_ENGINE_SDK_PATHS_H_
#define KERNEL_ENGINE_SDK_PATHS_H_

#include <stddef.h>
#include <stdio.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
#elif defined(__APPLE__)
#include <mach-o/dyld.h>
#include <stdint.h>
#else
#include <sys/types.h>
extern ssize_t readlink(const char *restrict path, char *restrict buffer, size_t size);
#endif

/**
 * @file
 * Where a program's files lie relative to its executable, answered by the operating system.
 */

/**
 * Writes into @p out the directory holding the running executable, without a trailing separator.
 * @param out      Receives the directory, terminated.
 * @param capacity The bytes @p out holds.
 * @return 1, or 0 when the system does not answer or the directory does not fit.
 */
static inline int ke_sdk_executable_dir(char *out, size_t capacity)
{
    char path[4096];
    size_t length = 0;
#if defined(_WIN32)
    DWORD written = GetModuleFileNameA(NULL, path, (DWORD)sizeof path);
    if (written == 0 || written >= sizeof path) return 0;
    length = written;
#elif defined(__APPLE__)
    uint32_t size = (uint32_t)sizeof path;
    if (_NSGetExecutablePath(path, &size) != 0) return 0;
    length = strlen(path);
#else
    ssize_t written = readlink("/proc/self/exe", path, sizeof path - 1);
    if (written <= 0) return 0;
    length = (size_t)written;
#endif
    path[length] = '\0';
    while (length > 0 && path[length - 1] != '/' && path[length - 1] != '\\') --length;
    if (length > 0) --length;
    if (length + 1 > capacity) return 0;
    memcpy(out, path, length);
    out[length] = '\0';
    return 1;
}

/**
 * Writes into @p out the path of @p name inside the directory of the running executable.
 * @param name [utf8] A file or directory name relative to that directory.
 * @return 1, or 0 when the directory is unknown or the path does not fit.
 */
static inline int ke_sdk_beside_executable(char *out, size_t capacity, const char *name)
{
    char dir[4096];
    if (!ke_sdk_executable_dir(dir, sizeof dir)) return 0;
    int written = snprintf(out, capacity, "%s/%s", dir, name);
    return written > 0 && (size_t)written < capacity;
}

#endif
