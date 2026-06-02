#ifndef KERNEL_ENGINE_FRAMEWORK_TYPES_H_
#define KERNEL_ENGINE_FRAMEWORK_TYPES_H_

// Cross-binding C ABI symbol-visibility macro for src/c/framework. Mirrors
// the kernel's KE_API pattern (KE_KERNEL_STATIC / KE_KERNEL_EXPORT). Every
// public framework header tags its exported declarations with KE_FRAMEWORK_API
// so consumers — be it the C# binding (P/Invoke loads the shared lib), a
// future Lua binding, or a pure-C game — see them.

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

#endif // KERNEL_ENGINE_FRAMEWORK_TYPES_H_
