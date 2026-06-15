#ifndef KERNEL_ENGINE_COMMON_EXPORT_H_
#define KERNEL_ENGINE_COMMON_EXPORT_H_

// Platform visibility primitives.
#if defined(_WIN32) || defined(__CYGWIN__)
#  define KE_EXPORT __declspec(dllexport)
#  define KE_IMPORT __declspec(dllimport)
#  define KE_HIDDEN
#else
#  define KE_EXPORT __attribute__((visibility("default")))
#  define KE_IMPORT __attribute__((visibility("default")))
#  define KE_HIDDEN __attribute__((visibility("hidden")))
#endif

// ── Kernel built-in exports ───────────────────────────────────────────────────
// Symbols compiled into ke_kernel (allocator, logger, ecs, resource_cache,
// frame_packet). CMake defines KE_KERNEL_STATIC or KE_KERNEL_EXPORT.
// Per-domain names are aliases so each header can advertise its own macro.

#ifdef KE_KERNEL_STATIC
#  define KE_API
#  define KE_ALLOCATOR_API
#  define KE_LOGGER_API
#  define KE_ECS_API
#  define KE_RESOURCE_CACHE_API
#  define KE_FRAME_PACKET_API
#elif defined(KE_KERNEL_EXPORT)
#  define KE_API                KE_EXPORT
#  define KE_ALLOCATOR_API      KE_EXPORT
#  define KE_LOGGER_API         KE_EXPORT
#  define KE_ECS_API            KE_EXPORT
#  define KE_RESOURCE_CACHE_API KE_EXPORT
#  define KE_FRAME_PACKET_API   KE_EXPORT
#else
#  define KE_API                KE_IMPORT
#  define KE_ALLOCATOR_API      KE_IMPORT
#  define KE_LOGGER_API         KE_IMPORT
#  define KE_ECS_API            KE_IMPORT
#  define KE_RESOURCE_CACHE_API KE_IMPORT
#  define KE_FRAME_PACKET_API   KE_IMPORT
#endif

// ── ke_runtime plugin exports ─────────────────────────────────────────────────
// Functions compiled into ke_runtime (not ke_kernel).
// ke_runtime CMakeLists defines KE_RUNTIME_STATIC or KE_RUNTIME_EXPORT.
#ifdef KE_RUNTIME_STATIC
#  define KE_RUNTIME_API
#elif defined(KE_RUNTIME_EXPORT)
#  define KE_RUNTIME_API KE_EXPORT
#else
#  define KE_RUNTIME_API KE_IMPORT
#endif

#endif // KERNEL_ENGINE_COMMON_EXPORT_H_
