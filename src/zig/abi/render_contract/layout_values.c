#include <stddef.h>
#include <kernel_engine/render/component_fields.h>
#include <kernel_engine/render/resource_groups.h>
#include <kernel_engine/render/service/pass_context.h>
#include <kernel_engine/render/ui/component_fields.h>
const unsigned long long layout_values[] = {
    sizeof(ke_render_pass_ctx),
    offsetof(ke_render_pass_ctx, handle),
    offsetof(ke_render_pass_ctx, read),
    offsetof(ke_render_pass_ctx, write),
    offsetof(ke_render_pass_ctx, begin_render),
    offsetof(ke_render_pass_ctx, begin_compute),
    offsetof(ke_render_pass_ctx, encoder),
    offsetof(ke_render_pass_ctx, query_ext),
    offsetof(ke_render_pass_ctx, backbuffer_size),
    offsetof(ke_render_pass_ctx, color_source),
    0,
};
