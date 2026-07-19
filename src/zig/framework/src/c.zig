// Single @cImport for the whole plugin.
//
// Separate @cImport blocks produce separate types even when they include the
// same header, so a struct passed between two framework translation units would
// not typecheck. Every file imports `c` from here instead.

pub const c = @cImport({
    @cInclude("kernel_engine/common/error.h");
    @cInclude("kernel_engine/common/math.h");
    @cInclude("kernel_engine/ecs/ke_ecs.h");
    @cInclude("kernel_engine/ecs/variant.h");
    @cInclude("kernel_engine/runtime/system_ctx.h");
    @cInclude("kernel_engine/asset/mesh_shape.h");
    @cInclude("kernel_engine/framework/components.h");
    @cInclude("kernel_engine/framework/asset_resolver_create.h");
    @cInclude("kernel_engine/framework/scene_tree_create.h");
    @cInclude("kernel_engine/framework/scene_loader_create.h");
    @cInclude("kernel_engine/framework/world_create.h");
    @cInclude("kernel_engine/framework/input_actions_create.h");
    @cInclude("toml.h");
});
