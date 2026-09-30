pub const c = @cImport({
    @cInclude("kernel_engine/common/error.h");
    @cInclude("kernel_engine/ecs/ecs.h");
    @cInclude("kernel_engine/logger/logger.h");
    @cInclude("kernel_engine/runtime/runtime.h");
    @cInclude("kernel_engine/runtime/system_ctx.h");
    @cInclude("kernel_engine/spatial/transform.h");
    @cInclude("kernel_engine/spatial/component_fields.h");
    @cInclude("kernel_engine/framework/components.h");
    @cInclude("kernel_engine/physics/physics_2d.h");
    @cInclude("kernel_engine/physics/components.h");
    @cInclude("kernel_engine/physics/component_fields.h");
    @cInclude("kernel_engine/framework/world.h");
    @cInclude("kernel_engine/physics/body2d/body2d_module.h");
});
