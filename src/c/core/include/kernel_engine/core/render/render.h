#ifndef KERNEL_ENGINE_CORE_RENDER_RENDER_H_
#define KERNEL_ENGINE_CORE_RENDER_RENDER_H_

#include <kernel_engine/core/common/error.h>
#include <kernel_engine/core/context/types.h>
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

        ke_result (*set_orthographic)(struct ke_render *self, bool enabled);
        ke_result (*clear_color)(struct ke_render *self, float r, float g, float b, float a);
        ke_result (*draw_node)(struct ke_render *self, void *node_handle);
        ke_result (*set_node_shape)(struct ke_render *self, void *node_handle, int shape);
        ke_result (*set_node_color)(struct ke_render *self, void *node_handle, float r, float g, float b, float a);
    } ke_render;

#ifdef __cplusplus
}
#endif

#endif // KERNEL_ENGINE_CORE_RENDER_RENDER_H_
