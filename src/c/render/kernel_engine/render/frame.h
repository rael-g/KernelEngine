#ifndef KERNEL_ENGINE_RENDER_FRAME_H_
#define KERNEL_ENGINE_RENDER_FRAME_H_

#include <kernel_engine/ecs/ecs.h>
#include <kernel_engine/render/gpu/gpu_enums.h>
#include <kernel_engine/render_graph/render_graph.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /**
     * [interface] The frame every pass declares into: the render graph's frame, begun with the frame's
     * colour, depth and output, and executed and presented once the passes are declared. Each resource
     * it answers is one of the frame being declared, valid until the next frame begins.
     */
    typedef struct ke_render_frame
    {
        void *handle;
        /**
         * The tag every system that declares a pass writes, which puts those systems in a series, and
         * that the systems beginning and ending the frame touch.
         */
        ke_component_id (*frame_cid)(struct ke_render_frame *self);
        /** The graph the frame's passes are declared into. */
        ke_render_graph *(*graph)(struct ke_render_frame *self);
        /** Whether a frame is being declared; when not, a pass declares nothing. */
        bool (*live)(struct ke_render_frame *self);
        /** The frame's colour, which the passes up to KE_RENDER_STAGE_HDR_POST draw into; cleared when the frame begins. */
        ke_render_graph_resource (*color)(struct ke_render_frame *self);
        /** The frame's depth, cleared when the frame begins. */
        ke_render_graph_resource (*depth)(struct ke_render_frame *self);
        /** The texture the frame is presented from, imported from the render target, which the passes from
         *  KE_RENDER_STAGE_TONEMAP on draw into. */
        ke_render_graph_resource (*output)(struct ke_render_frame *self);
        /**
         * Says that a pass declared in this frame writes every texel of the output from the colour; without
         * it, the frame copies the colour into the output at KE_RENDER_STAGE_TONEMAP.
         */
        void (*claim_output)(struct ke_render_frame *self);
        /**
         * Publishes @p resource under @p name for the passes declared after it in this frame; a name
         * published again is replaced. What a frame published is forgotten when the next begins.
         * @param name [utf8] Copied by the call.
         * @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a NULL name; KE_RESULT_OUT_OF_MEMORY.
         */
        ke_result (*publish)(struct ke_render_frame *self, const char *name, ke_render_graph_resource resource);
        /**
         * The resource published under @p name in this frame; KE_RENDER_GRAPH_RESOURCE_INVALID when none is.
         * @param name [utf8]
         */
        ke_render_graph_resource (*find)(struct ke_render_frame *self, const char *name);
        /** Texel format of the colour the frame begins with. */
        ke_gpu_texture_format (*color_format)(struct ke_render_frame *self);
        /** Texel format of the frame's depth. */
        ke_gpu_texture_format (*depth_format)(struct ke_render_frame *self);
        /** Texel format of the frame's output. */
        ke_gpu_texture_format (*output_format)(struct ke_render_frame *self);
    } ke_render_frame;

    /// [owner]
    typedef struct ke_render_frame_handle
    {
        ke_render_frame *ref;
        void (*destroy)(ke_render_frame *self);
    } ke_render_frame_handle;

#ifdef __cplusplus
}
#endif

#endif
