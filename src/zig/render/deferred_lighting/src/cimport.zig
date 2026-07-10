// Single shared @cImport for this plugin's Zig files.
pub const c = @cImport({
    @cInclude("kernel_engine/common/error.h");
    @cInclude("kernel_engine/ecs/ecs.h");
    @cInclude("kernel_engine/logger/logger.h");
    @cInclude("kernel_engine/runtime/runtime.h");
    @cInclude("kernel_engine/runtime/system_ctx.h");
    @cInclude("kernel_engine/spatial/transform.h");
    @cInclude("kernel_engine/render/components.h");
    @cInclude("kernel_engine/render/gpu_device.h");
    @cInclude("kernel_engine/render/gpu_commands.h");
    @cInclude("kernel_engine/render/core/render_core.h");
    @cInclude("kernel_engine/render/core/pass_context.h");
    @cInclude("kernel_engine/render/deferred_lighting/deferred_lighting_create.h");
});
