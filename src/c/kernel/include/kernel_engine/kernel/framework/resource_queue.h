#ifndef KERNEL_ENGINE_FRAMEWORK_RESOURCE_QUEUE_H_
#define KERNEL_ENGINE_FRAMEWORK_RESOURCE_QUEUE_H_

// ke_resource_queue — language-agnostic command queue routing GPU resource
// create/destroy calls from any thread to a single executor thread (typically
// ke.render). Mirrors the C# ResourceCommandQueue and replaces it as the
// canonical implementation: bindings (C#, Lua) submit commands, ke.render
// drains them and dispatches against the injected ke_render vtable.
//
// Each create command produces a ke_resource_future the caller waits on to
// receive the resulting handle. Destroy commands accept a NULL out_future
// (fire-and-forget) since they have no result.
//
// Variable-length payloads (vertex / index / pixel arrays) are copied into the
// queue's internal allocator on submit; callers can immediately free their
// own buffers.

#include <kernel_engine/kernel/framework/framework_export.h>
#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/common/handles.h>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/render/material.h>
#include <kernel_engine/kernel/render/mesh.h>
#include <stdint.h>

struct ke_render;

#ifdef __cplusplus
extern "C"
{
#endif

    typedef enum ke_resource_command_kind
    {
        KE_RESOURCE_CMD_CREATE_MESH        = 0,
        KE_RESOURCE_CMD_DESTROY_MESH       = 1,
        KE_RESOURCE_CMD_CREATE_TEXTURE     = 2,
        KE_RESOURCE_CMD_CREATE_CUBEMAP     = 3,
        KE_RESOURCE_CMD_DESTROY_TEXTURE    = 4,
        KE_RESOURCE_CMD_CREATE_MATERIAL    = 5,
        KE_RESOURCE_CMD_DESTROY_MATERIAL   = 6,
        KE_RESOURCE_CMD_CREATE_SHADOW_MAP  = 7,
        KE_RESOURCE_CMD_DESTROY_SHADOW_MAP = 8,
    } ke_resource_command_kind;

    typedef struct ke_create_mesh_cmd
    {
        const ke_vertex *vertices;
        uint32_t         vertex_count;
        const uint16_t  *indices;
        uint32_t         index_count;
    } ke_create_mesh_cmd;

    typedef struct ke_create_texture_cmd
    {
        uint32_t       width;
        uint32_t       height;
        const uint8_t *pixels;        ///< RGBA8: width*height*4 bytes
    } ke_create_texture_cmd;

    typedef struct ke_create_cubemap_cmd
    {
        uint32_t       face_size;
        const uint8_t *pixels;        ///< 6 faces * face_size * face_size * 4 bytes
    } ke_create_cubemap_cmd;

    typedef struct ke_create_material_cmd
    {
        ke_material material;
    } ke_create_material_cmd;

    typedef struct ke_create_shadow_map_cmd
    {
        uint32_t width;
        uint32_t height;
    } ke_create_shadow_map_cmd;

    typedef struct ke_destroy_handle_cmd
    {
        uint32_t handle;
    } ke_destroy_handle_cmd;

    typedef struct ke_resource_command
    {
        ke_resource_command_kind kind;
        union
        {
            ke_create_mesh_cmd       create_mesh;
            ke_create_texture_cmd    create_texture;
            ke_create_cubemap_cmd    create_cubemap;
            ke_create_material_cmd   create_material;
            ke_create_shadow_map_cmd create_shadow_map;
            ke_destroy_handle_cmd    destroy;
        } u;
    } ke_resource_command;

    // ── Future ──────────────────────────────────────────────────────────────

    typedef struct ke_resource_future ke_resource_future;

    /// Blocks until the future completes (or until timeout_ms elapses; pass 0
    /// for non-blocking poll, UINT32_MAX for infinite wait). Returns the
    /// status the queue stored when executing the command:
    /// KE_OK for success, KE_ERROR* on renderer failure, KE_ERROR_INVALID_ARGUMENT
    /// when not yet ready (only when timeout_ms is 0).
    KE_FRAMEWORK_API ke_result ke_resource_future_wait(ke_resource_future *future,
                                                        uint32_t            timeout_ms);

    /// After a successful wait, returns the handle the renderer produced
    /// (0 for destroy commands).
    KE_FRAMEWORK_API uint32_t ke_resource_future_get_handle(ke_resource_future *future);

    /// Releases the future. Must be called by the caller of submit().
    KE_FRAMEWORK_API void ke_resource_future_release(ke_resource_future *future);

    // ── Queue ───────────────────────────────────────────────────────────────

    typedef struct ke_resource_queue
    {
        void *handle;

        /// Submits a command for later execution. Returns the future via out_future
        /// (caller releases). Pass NULL for out_future to fire-and-forget. The
        /// queue copies any embedded array data; the caller may free its own buffers
        /// as soon as submit returns.
        ke_result (*submit)(struct ke_resource_queue *self,
                            const ke_resource_command *cmd,
                            ke_resource_future       **out_future);

        /// Executes up to max_count commands against the renderer. Returns the
        /// number drained. Pass 0 for max_count to drain everything currently queued.
        /// Must be called on the renderer thread.
        uint32_t (*drain)(struct ke_resource_queue *self,
                          struct ke_render         *renderer,
                          uint32_t                   max_count);

        void (*destroy)(struct ke_resource_queue *self);
    } ke_resource_queue;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_FRAMEWORK_RESOURCE_QUEUE_H_
