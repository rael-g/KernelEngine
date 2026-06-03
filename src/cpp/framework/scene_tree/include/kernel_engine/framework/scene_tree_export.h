#ifndef KERNEL_ENGINE_FRAMEWORK_SCENE_TREE_EXPORT_H_
#define KERNEL_ENGINE_FRAMEWORK_SCENE_TREE_EXPORT_H_

#if defined(_WIN32) || defined(__CYGWIN__)
#define KE_SCENE_TREE_HELPER_EXPORT __declspec(dllexport)
#define KE_SCENE_TREE_HELPER_IMPORT __declspec(dllimport)
#else
#define KE_SCENE_TREE_HELPER_EXPORT __attribute__((visibility("default")))
#define KE_SCENE_TREE_HELPER_IMPORT __attribute__((visibility("default")))
#endif

#ifdef KE_SCENE_TREE_STATIC
#define KE_SCENE_TREE_API
#else
#ifdef KE_SCENE_TREE_EXPORT
#define KE_SCENE_TREE_API KE_SCENE_TREE_HELPER_EXPORT
#else
#define KE_SCENE_TREE_API KE_SCENE_TREE_HELPER_IMPORT
#endif
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_SCENE_TREE_EXPORT_H_
