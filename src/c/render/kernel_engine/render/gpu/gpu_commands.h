#ifndef KERNEL_ENGINE_RENDER_GPU_COMMANDS_H_
#define KERNEL_ENGINE_RENDER_GPU_COMMANDS_H_

#include <kernel_engine/render/gpu/gpu_device.h>

#ifdef __cplusplus
extern "C"
{
#endif

// ══════════════════════════════════════════════════════════════════════════
// L4 — Typed recording objects
//
// Each struct holds a raw backend handle and a device backref. Methods
// route to the device's backing `rp_*` / `cp_*` / `encoder_*` slots,
// adding type safety without touching the L3 interface.
// ══════════════════════════════════════════════════════════════════════════

// ── Render pass ───────────────────────────────────────────────────────────

struct ke_gpu_render_pass
{
    void              *handle;
    ke_gpu_device     *device;

    void (*set_pipeline)(struct ke_gpu_render_pass *self, ke_gpu_pipeline pipe);
    void (*set_bind_group)(struct ke_gpu_render_pass *self, uint32_t group_index,
                           ke_gpu_bind_group bg, const uint32_t *dynamic_offsets,
                           uint32_t dyn_count);
    void (*set_vertex_buffer)(struct ke_gpu_render_pass *self, uint32_t slot,
                              ke_gpu_buffer b, size_t offset);
    void (*set_index_buffer)(struct ke_gpu_render_pass *self, ke_gpu_buffer b,
                             ke_gpu_index_format fmt, size_t offset);
    void (*set_viewport)(struct ke_gpu_render_pass *self, float x, float y,
                         float w, float h, float min_depth, float max_depth);
    void (*set_scissor)(struct ke_gpu_render_pass *self, int32_t x, int32_t y,
                        uint32_t w, uint32_t h);
    void (*draw)(struct ke_gpu_render_pass *self, uint32_t vert_count,
                 uint32_t inst_count, uint32_t first_vert, uint32_t first_inst);
    void (*draw_indexed)(struct ke_gpu_render_pass *self, uint32_t idx_count,
                         uint32_t inst_count, uint32_t first_idx,
                         int32_t base_vert, uint32_t first_inst);
    void (*draw_indirect)(struct ke_gpu_render_pass *self,
                          ke_gpu_buffer indirect_buf, size_t offset);
    void (*end)(struct ke_gpu_render_pass *self);
};

// ── Compute pass ───────────────────────────────────────────────────────────

struct ke_gpu_compute_pass
{
    void          *handle;
    ke_gpu_device *device;

    void (*set_pipeline)(struct ke_gpu_compute_pass *self, ke_gpu_pipeline pipe);
    void (*set_bind_group)(struct ke_gpu_compute_pass *self, uint32_t group_index,
                           ke_gpu_bind_group bg, const uint32_t *dynamic_offsets,
                           uint32_t dyn_count);
    void (*dispatch)(struct ke_gpu_compute_pass *self,
                     uint32_t x, uint32_t y, uint32_t z);
    void (*dispatch_indirect)(struct ke_gpu_compute_pass *self,
                              ke_gpu_buffer indirect_buf, size_t offset);
    void (*end)(struct ke_gpu_compute_pass *self);
};

// ── Command encoder ────────────────────────────────────────────────────────

struct ke_gpu_command_encoder
{
    void          *handle;
    ke_gpu_device *device;

    struct ke_gpu_render_pass  *(*begin_render_pass)(struct ke_gpu_command_encoder *self,
                                                     const ke_gpu_render_pass_params *p);
    struct ke_gpu_compute_pass *(*begin_compute_pass)(struct ke_gpu_command_encoder *self);
    void (*pipeline_barrier)(struct ke_gpu_command_encoder *self, const ke_gpu_barrier *b);
    void (*copy_buffer_to_buffer)(struct ke_gpu_command_encoder *self,
                                  ke_gpu_buffer src, size_t src_offset,
                                  ke_gpu_buffer dst, size_t dst_offset, size_t size);
    void (*copy_buffer_to_texture)(struct ke_gpu_command_encoder *self,
                                   ke_gpu_buffer src, size_t src_offset,
                                   ke_gpu_texture dst,
                                   uint32_t dst_x, uint32_t dst_y, uint32_t dst_z,
                                   uint32_t width, uint32_t height);
    // Whole-texture same-format copy (mip 0, layer 0, full extent). The scene-color
    // snapshot a refraction pass reads must be a distinct texture from the one it
    // writes — sampling and writing the same render target in one pass is not
    // representable by the API. Must be issued outside an active render pass.
    void (*copy_texture_to_texture)(struct ke_gpu_command_encoder *self,
                                    ke_gpu_texture src, ke_gpu_texture dst,
                                    uint32_t width, uint32_t height);
    struct ke_gpu_command_buffer *(*finish)(struct ke_gpu_command_encoder *self);
    void (*destroy)(struct ke_gpu_command_encoder *self);
};

// ── Command buffer ─────────────────────────────────────────────────────────

struct ke_gpu_command_buffer
{
    void          *handle;
    ke_gpu_device *device;

    void (*destroy)(struct ke_gpu_command_buffer *self);
};

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_RENDER_GPU_COMMANDS_H_
