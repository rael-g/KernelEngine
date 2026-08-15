#ifndef KERNEL_ENGINE_COMMON_EXPORT_H_
#define KERNEL_ENGINE_COMMON_EXPORT_H_

#if defined(_WIN32) || defined(__CYGWIN__)
#  define KE_EXPORT __declspec(dllexport)
#  define KE_IMPORT __declspec(dllimport)
#  define KE_HIDDEN
#else
#  define KE_EXPORT __attribute__((visibility("default")))
#  define KE_IMPORT __attribute__((visibility("default")))
#  define KE_HIDDEN __attribute__((visibility("hidden")))
#endif

#ifdef KE_ECS_STATIC
#  define KE_ECS_API
#elif defined(KE_ECS_EXPORT)
#  define KE_ECS_API KE_EXPORT
#else
#  define KE_ECS_API KE_IMPORT
#endif

#ifdef KE_FRAME_PACKET_STATIC
#  define KE_FRAME_PACKET_API
#elif defined(KE_FRAME_PACKET_EXPORT)
#  define KE_FRAME_PACKET_API KE_EXPORT
#else
#  define KE_FRAME_PACKET_API KE_IMPORT
#endif

#define KE_ALLOCATOR_API

#ifdef KE_RUNTIME_STATIC
#  define KE_RUNTIME_API
#elif defined(KE_RUNTIME_EXPORT)
#  define KE_RUNTIME_API KE_EXPORT
#else
#  define KE_RUNTIME_API KE_IMPORT
#endif

#endif
