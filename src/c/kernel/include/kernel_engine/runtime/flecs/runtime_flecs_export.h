#ifndef KERNEL_ENGINE_RUNTIME_FLECS_EXPORT_H_
#define KERNEL_ENGINE_RUNTIME_FLECS_EXPORT_H_

#if defined(_WIN32) || defined(__CYGWIN__)
#define KE_RUNTIME_FLECS_HELPER_EXPORT __declspec(dllexport)
#define KE_RUNTIME_FLECS_HELPER_IMPORT __declspec(dllimport)
#else
#define KE_RUNTIME_FLECS_HELPER_EXPORT __attribute__((visibility("default")))
#define KE_RUNTIME_FLECS_HELPER_IMPORT __attribute__((visibility("default")))
#endif

#ifdef KE_RUNTIME_FLECS_STATIC
#define KE_RUNTIME_FLECS_API
#else
#ifdef KE_RUNTIME_FLECS_EXPORT
#define KE_RUNTIME_FLECS_API KE_RUNTIME_FLECS_HELPER_EXPORT
#else
#define KE_RUNTIME_FLECS_API KE_RUNTIME_FLECS_HELPER_IMPORT
#endif
#endif

#endif // KERNEL_ENGINE_RUNTIME_FLECS_EXPORT_H_
