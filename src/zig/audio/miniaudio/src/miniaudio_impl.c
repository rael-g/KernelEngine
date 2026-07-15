/* miniaudio is header-only; this translation unit compiles the
 * implementation. Kept out of @cImport because translate-c cannot lower
 * miniaudio's internals, and it keeps the implementation scoped to a single
 * translation unit (no symbol collision with any other plugin pulling
 * miniaudio in). */
#define MINIAUDIO_IMPLEMENTATION
#include <miniaudio.h>
