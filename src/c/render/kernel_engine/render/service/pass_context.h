#ifndef KERNEL_ENGINE_RENDER_CORE_PASS_CONTEXT_H_
#define KERNEL_ENGINE_RENDER_CORE_PASS_CONTEXT_H_

#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/render/gpu/gpu_commands.h>

#ifdef __cplusplus
extern "C"
{
#endif

// ══════════════════════════════════════════════════════════════════════════
// L5 — Per-pass recording context
//
// Handed to a render system's body by ke_render_service_begin_pass. Resolves the
// pass's declared resources to live GPU views, opens L4 recording objects with
// the pass's writes already bound as attachments, and reaches device
// extensions. Lifetime = the begin_pass/end_pass span; do not retain.
// ══════════════════════════════════════════════════════════════════════════

typedef struct ke_render_pass_ctx ke_render_pass_ctx;

struct ke_render_pass_ctx
{
    void *handle;

    // Declared resources → live views. `name` must be one this pass declared;
    // an undeclared name returns KE_GPU_INVALID_HANDLE.
    ke_gpu_texture_view (*read)(struct ke_render_pass_ctx *self, const char *name);
    ke_gpu_texture_view (*write)(struct ke_render_pass_ctx *self, const char *name);

    // Open recording. The pass's declared color/depth writes are already set up
    // as attachments; the returned L4 object records draws/dispatches.
    struct ke_gpu_render_pass  *(*begin_render)(struct ke_render_pass_ctx *self);
    struct ke_gpu_compute_pass *(*begin_compute)(struct ke_render_pass_ctx *self);

    // Escape hatches for capability the core does not wrap: the raw encoder
    // (to feed an extension dispatch) and the typed extension vtable
    // (NULL when the backend lacks it).
    struct ke_gpu_command_encoder *(*encoder)(struct ke_render_pass_ctx *self);
    const void *(*query_ext)(struct ke_render_pass_ctx *self, const char *ext_name);

    void (*backbuffer_size)(struct ke_render_pass_ctx *self, uint32_t *out_w, uint32_t *out_h);
};

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_RENDER_CORE_PASS_CONTEXT_H_
