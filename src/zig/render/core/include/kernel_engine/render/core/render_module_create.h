#pragma once

#include <kernel_engine/render/core/render_core_create.h>
#include <kernel_engine/runtime/runtime.h>

#ifdef __cplusplus
extern "C"
{
#endif

typedef struct ke_render_module ke_render_module;

typedef struct ke_render_module_handle
{
    ke_render_module *ref;
    void (*destroy)(ke_render_module *self);
} ke_render_module_handle;

// Installs the render path into a runtime: builds the render core over the
// shared ecs + a caller-created GPU device. No pass is imposed — when
// default_passes is non-zero it registers the conventional chain (begin → clear
// → forward → end) as KE_PHASE_RENDER systems, ordered by the runtime via the
// backbuffer tag-cid; otherwise the game wires its own passes. The app drives it
// by ticking the runtime. Inputs are borrowed (the device stays caller-owned)
// and must outlive the handle; ref is NULL on failure.
KE_RENDER_CORE_API ke_render_module_handle
ke_render_module_create(ke_runtime *runtime, ke_ecs *ecs, ke_gpu_device *device,
                        ke_bool default_passes, ke_error **out_error);

// Borrows the render core the module owns — used to upload meshes and declare
// resources. Valid for the module's lifetime; the caller must not destroy it.
KE_RENDER_CORE_API ke_render_core *ke_render_module_core(ke_render_module *module);

#ifdef __cplusplus
}
#endif
