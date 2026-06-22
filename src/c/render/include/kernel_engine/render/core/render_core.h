#ifndef KERNEL_ENGINE_RENDER_CORE_RENDER_CORE_H_
#define KERNEL_ENGINE_RENDER_CORE_RENDER_CORE_H_

#include <kernel_engine/common/error.h>
#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/render/gpu_device.h>
#include <kernel_engine/render/core/pass_context.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

// Opaque — the runtime's per-system component funnel (kernel_engine/runtime/system_ctx.h).
typedef struct ke_system_ctx ke_system_ctx;

// ══════════════════════════════════════════════════════════════════════════
// L5 — Render core service
//
// Owns the transient render-target pool, the resource registry, and barrier
// tracking. It does NOT order passes: a render pass is a plain runtime system,
// and the runtime's wave-builder orders them. Each declared resource is minted
// as a zero-size tag component (its cid is placed in a pass-system's
// access_list) so a texture dependency becomes an ordinary write-before-read
// edge for the same wave-builder that orders sim systems.
// ══════════════════════════════════════════════════════════════════════════

typedef struct ke_render_core ke_render_core;

typedef enum ke_render_resource_type
{
    KE_RENDER_RESOURCE_TEXTURE = 0,
    KE_RENDER_RESOURCE_BUFFER  = 1,
} ke_render_resource_type;

typedef enum ke_render_size_mode
{
    KE_RENDER_SIZE_ABSOLUTE               = 0,
    KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER = 1,
} ke_render_size_mode;

typedef struct ke_render_resource_desc
{
    const char             *name;
    ke_render_resource_type type;
    ke_gpu_texture_format   format;
    ke_render_size_mode     size_mode;
    uint32_t                width;   // used when size_mode = ABSOLUTE
    uint32_t                height;
    float                   scale_x; // used when size_mode = RELATIVE_TO_BACKBUFFER
    float                   scale_y;
} ke_render_resource_desc;

// A pass's declared resource I/O by name. The module turns these names into
// the access_list cids (via cid()) at register_system time; begin_pass uses the
// same names to resolve views and bind the writes as attachments.
typedef struct ke_render_pass_io
{
    const char *const *reads;
    uint32_t           reads_count;
    const char *const *writes;
    uint32_t           writes_count;
} ke_render_pass_io;

struct ke_render_core
{
    void *handle;

    // ── Setup (single thread, module on_load) ─────────────────────────────
    // Declares a transient resource the core allocates and recycles; returns
    // the tag-component cid to place in pass access_lists.
    ke_component_id (*declare)(struct ke_render_core *self,
                               const ke_render_resource_desc *desc, ke_error **out_error);
    // Imports an externally-owned texture under `name`; returns its tag cid.
    ke_component_id (*import_texture)(struct ke_render_core *self, const char *name,
                                      ke_gpu_texture tex, ke_error **out_error);
    // The tag cid previously minted for `name` (KE_COMPONENT_INVALID if unknown).
    ke_component_id (*cid)(struct ke_render_core *self, const char *name);

    // ── Execute (inside a render system's body) ───────────────────────────
    struct ke_render_pass_ctx *(*begin_pass)(struct ke_render_core *self,
                                             ke_system_ctx *sys,
                                             const ke_render_pass_io *io);
    void (*end_pass)(struct ke_render_core *self, struct ke_render_pass_ctx *ctx);

    // ── Frame boundary (module wires these as the first/last render systems) ─
    // begin_frame acquires the backbuffer — a built-in resource named
    // "backbuffer", auto-declared at create. end_frame submits the passes'
    // command buffers in the order the runtime ran them, then presents.
    ke_bool (*begin_frame)(struct ke_render_core *self, ke_error **out_error);
    ke_bool (*end_frame)(struct ke_render_core *self, ke_error **out_error);
};

typedef struct ke_render_core_handle
{
    ke_render_core *ref;
    void (*destroy)(ke_render_core *self);
} ke_render_core_handle;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_RENDER_CORE_RENDER_CORE_H_
