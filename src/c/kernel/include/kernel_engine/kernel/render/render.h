#ifndef KERNEL_ENGINE_KERNEL_RENDER_RENDER_H_
#define KERNEL_ENGINE_KERNEL_RENDER_RENDER_H_

#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/common/math.h>
#include <kernel_engine/kernel/context/types.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define KE_ID_RENDER "ke_render"

    /// @brief Public interface for rendering operations.
    typedef struct ke_render
    {
        void *handle;
        void (*destroy)(struct ke_render *self);

        ke_result (*on_initialize)(struct ke_render *self);
        ke_result (*on_shutdown)(struct ke_render *self);

        ke_result (*set_orthographic)(struct ke_render *self, bool enabled);
        ke_result (*clear_color)(struct ke_render *self, float r, float g, float b, float a);
        
        /// @brief Submits a draw command with a world transform.
        ke_result (*submit)(struct ke_render *self, const ke_mat4 *transform);

        ke_result (*draw_node)(struct ke_render *self, void *node_handle);
        ke_result (*set_node_shape)(struct ke_render *self, void *node_handle, int shape);
        ke_result (*set_node_color)(struct ke_render *self, void *node_handle, float r, float g, float b, float a);
    } ke_render;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_KERNEL_RENDER_RENDER_H_
