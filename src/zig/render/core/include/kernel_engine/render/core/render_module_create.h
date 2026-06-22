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
// shared ecs + a caller-created GPU device, and registers the frame's render
// passes as KE_PHASE_RENDER systems (ordered by the runtime via the backbuffer
// tag-cid). The app drives it by ticking the runtime. Inputs are borrowed (the
// device stays caller-owned) and must outlive the handle; ref is NULL on failure.
KE_RENDER_CORE_API ke_render_module_handle
ke_render_module_create(ke_runtime *runtime, ke_ecs *ecs, ke_gpu_device *device,
                        ke_error **out_error);

#ifdef __cplusplus
}
#endif
