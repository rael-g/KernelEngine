#ifndef KERNEL_ENGINE_RENDER_CORE_PASS_CONTEXT_H_
#define KERNEL_ENGINE_RENDER_CORE_PASS_CONTEXT_H_

#include <kernel_engine/render/gpu/gpu_device.h>
#include <kernel_engine/render/gpu/gpu_commands.h>

#ifdef __cplusplus
extern "C"
{
#endif

typedef struct ke_render_pass_ctx ke_render_pass_ctx;

struct ke_render_pass_ctx
{
    void *handle;

    ke_gpu_texture_view (*read)(struct ke_render_pass_ctx *self, const char *name);
    ke_gpu_texture_view (*write)(struct ke_render_pass_ctx *self, const char *name);

    struct ke_gpu_render_pass  *(*begin_render)(struct ke_render_pass_ctx *self);
    struct ke_gpu_compute_pass *(*begin_compute)(struct ke_render_pass_ctx *self);

    struct ke_gpu_command_encoder *(*encoder)(struct ke_render_pass_ctx *self);
    const void *(*query_ext)(struct ke_render_pass_ctx *self, const char *ext_name);

    void (*backbuffer_size)(struct ke_render_pass_ctx *self, uint32_t *out_w, uint32_t *out_h);
};

#ifdef __cplusplus
}
#endif

#endif
