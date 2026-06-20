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

// ── Remaining centralized macros ─────────────────────────────────────────────
// Migrated domains use their own <domain>_export.h:
//   common         → common/common_export.h
//   logger         → logger/logger_export.h
//   input          → input/input_export.h
//   resource_cache → resource_cache/resource_cache_export.h

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
