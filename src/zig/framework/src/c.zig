
pub const c = @cImport({
    @cInclude("kernel_engine/common/error.h");
    @cInclude("kernel_engine/math/math.h");
    @cInclude("kernel_engine/ecs/ke_ecs.h");
    @cInclude("kernel_engine/ecs/variant.h");
    @cInclude("kernel_engine/ecs/component_field_write.h");
    @cInclude("kernel_engine/spatial/transform.h");
    @cInclude("kernel_engine/spatial/component_fields.h");
    @cInclude("kernel_engine/runtime/system_ctx.h");
    @cInclude("kernel_engine/asset/mesh_shape.h");
    @cInclude("kernel_engine/framework/components.h");
    @cInclude("kernel_engine/framework/asset_resolver_create.h");
    @cInclude("kernel_engine/framework/scene_tree_create.h");
    @cInclude("kernel_engine/framework/scene_hierarchy_create.h");
    @cInclude("kernel_engine/framework/scene_loader_create.h");
    @cInclude("kernel_engine/framework/signal_bus_create.h");
    @cInclude("kernel_engine/framework/script_host_create.h");
    @cInclude("kernel_engine/framework/world_create.h");
    @cInclude("kernel_engine/framework/input_actions_create.h");
    @cInclude("kernel_engine/logger/logger.h");
    @cInclude("kernel_engine/input/key.h");
    @cInclude("toml.h");
});
