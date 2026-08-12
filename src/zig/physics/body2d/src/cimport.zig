// Single @cImport for the plugin — separate blocks would produce distinct Zig
// types for the same C struct, so anything crossing between these files would
// stop typechecking.

pub const c = @cImport({
    @cInclude("kernel_engine/common/error.h");
    @cInclude("kernel_engine/ecs/ecs.h");
    @cInclude("kernel_engine/runtime/runtime.h");
    @cInclude("kernel_engine/runtime/system_ctx.h");
    @cInclude("kernel_engine/spatial/transform.h");
    @cInclude("kernel_engine/physics/physics_2d.h");
    @cInclude("kernel_engine/physics/components.h");
    @cInclude("kernel_engine/physics/body2d/body2d_module.h");
});
