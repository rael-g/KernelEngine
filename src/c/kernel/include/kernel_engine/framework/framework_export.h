#ifndef KERNEL_ENGINE_FRAMEWORK_EXPORT_H_
#define KERNEL_ENGINE_FRAMEWORK_EXPORT_H_

// Symbol-visibility macro for ke_framework. Mirrors KE_API in the kernel —
// each factory in the framework contract headers tags its declaration with
// KE_FRAMEWORK_API so the single src/cpp/framework/ plugin DLL exports it.

#if defined(_WIN32) || defined(__CYGWIN__)
#define KE_FRAMEWORK_HELPER_EXPORT __declspec(dllexport)
#define KE_FRAMEWORK_HELPER_IMPORT __declspec(dllimport)
#else
#define KE_FRAMEWORK_HELPER_EXPORT __attribute__((visibility("default")))
#define KE_FRAMEWORK_HELPER_IMPORT __attribute__((visibility("default")))
#endif

#ifdef KE_FRAMEWORK_STATIC
#define KE_FRAMEWORK_API
#else
#ifdef KE_FRAMEWORK_EXPORT
#define KE_FRAMEWORK_API KE_FRAMEWORK_HELPER_EXPORT
#else
#define KE_FRAMEWORK_API KE_FRAMEWORK_HELPER_IMPORT
#endif
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_EXPORT_H_
