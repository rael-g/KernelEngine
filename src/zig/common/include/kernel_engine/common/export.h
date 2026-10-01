#ifndef KERNEL_ENGINE_COMMON_EXPORT_H_
#define KERNEL_ENGINE_COMMON_EXPORT_H_

#if defined(_WIN32) || defined(__CYGWIN__)
#  define KE_EXPORT __declspec(dllexport)
#  define KE_IMPORT __declspec(dllimport)
#else
#  define KE_EXPORT __attribute__((visibility("default")))
#  define KE_IMPORT __attribute__((visibility("default")))
#endif

#endif
