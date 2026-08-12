// Single shared @cImport for every render-service Zig file. Two separate
// @cImport blocks produce distinct (incompatible) Zig types for the same C
// struct, even when textually identical, so every file here imports this `c`
// rather than re-@cInclude'ing its own copy.
pub const c = @cImport({
    @cInclude("kernel_engine/runtime/runtime.h");
    @cInclude("kernel_engine/runtime/system_ctx.h");
    @cInclude("kernel_engine/ecs/ke_ecs.h");
    @cInclude("kernel_engine/ecs/variant.h");
    @cInclude("kernel_engine/spatial/transform.h");
    @cInclude("kernel_engine/framework/world.h");
    @cInclude("kernel_engine/render/components.h");
    @cInclude("kernel_engine/render/gpu/gpu_device.h");
    @cInclude("kernel_engine/render/gpu/gpu_commands.h");
    @cInclude("kernel_engine/render/service/render_service.h");
    @cInclude("kernel_engine/render/service/pass_context.h");
    @cInclude("kernel_engine/render/service/render_service_create.h");
    @cInclude("kernel_engine/logger/logger.h");
});
