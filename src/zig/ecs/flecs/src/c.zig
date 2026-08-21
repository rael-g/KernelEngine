pub const c = @cImport({
    @cInclude("kernel_engine/ecs/ke_ecs_flecs.h");
    @cInclude("kernel_engine/ecs/component_field_write.h");
    @cInclude("flecs.h");
});
