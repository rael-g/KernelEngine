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

// ── Per-domain export macros ──────────────────────────────────────────────────
// Each domain DLL sets its own _EXPORT define (PRIVATE in CMake) when building.
// Consumers define nothing → KE_IMPORT. Static builds set _STATIC → empty.

// ke_common (error singletons + ke_error_set/is)
#ifdef KE_COMMON_STATIC
#  define KE_COMMON_API
#elif defined(KE_COMMON_EXPORT)
#  define KE_COMMON_API KE_EXPORT
#else
#  define KE_COMMON_API KE_IMPORT
#endif

// ke_logger_simple
#ifdef KE_LOGGER_STATIC
#  define KE_LOGGER_API
#elif defined(KE_LOGGER_EXPORT)
#  define KE_LOGGER_API KE_EXPORT
#else
#  define KE_LOGGER_API KE_IMPORT
#endif

// ke_input_default
#ifdef KE_INPUT_STATIC
#  define KE_INPUT_API
#elif defined(KE_INPUT_EXPORT)
#  define KE_INPUT_API KE_EXPORT
#else
#  define KE_INPUT_API KE_IMPORT
#endif

// ke_resource_cache_default
#ifdef KE_RESOURCE_CACHE_STATIC
#  define KE_RESOURCE_CACHE_API
#elif defined(KE_RESOURCE_CACHE_EXPORT)
#  define KE_RESOURCE_CACHE_API KE_EXPORT
#else
#  define KE_RESOURCE_CACHE_API KE_IMPORT
#endif

// ke_ecs_* (sparse set, registry — future)
#ifdef KE_ECS_STATIC
#  define KE_ECS_API
#elif defined(KE_ECS_EXPORT)
#  define KE_ECS_API KE_EXPORT
#else
#  define KE_ECS_API KE_IMPORT
#endif

// ke_render_frame_packet
#ifdef KE_FRAME_PACKET_STATIC
#  define KE_FRAME_PACKET_API
#elif defined(KE_FRAME_PACKET_EXPORT)
#  define KE_FRAME_PACKET_API KE_EXPORT
#else
#  define KE_FRAME_PACKET_API KE_IMPORT
#endif

// Generic KE_API — resolves to KE_COMMON_API for symbols in common headers.
// Legacy alias; prefer the domain-specific macro in new code.
#define KE_API KE_COMMON_API

// Allocator — internal impl dep, never exported to C# / plugin consumers.
#define KE_ALLOCATOR_API

// ── ke_runtime plugin exports ─────────────────────────────────────────────────
#ifdef KE_RUNTIME_STATIC
#  define KE_RUNTIME_API
#elif defined(KE_RUNTIME_EXPORT)
#  define KE_RUNTIME_API KE_EXPORT
#else
#  define KE_RUNTIME_API KE_IMPORT
#endif

#endif // KERNEL_ENGINE_COMMON_EXPORT_H_
