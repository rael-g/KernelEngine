// src/c/framework/src/framework.c
//
// Placeholder translation unit for ke_framework. The framework layer hosts
// portable building blocks (scene tree, scene loader, input actions, resource
// cache, node type registry, ...). Real implementations land in sibling .c
// files as each concept migrates from KernelEngine.Framework / KernelEngine.CSharp.
//
// Keeping this file ensures the shared library has at least one symbol to
// link until the first concept's .c lands.

#include <kernel_engine/framework/types.h>

KE_FRAMEWORK_API int ke_framework_abi_version(void) { return 1; }
