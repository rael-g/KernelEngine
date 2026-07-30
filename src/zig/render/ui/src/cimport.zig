// Single shared @cImport for this plugin's Zig files.
pub const c = @cImport({
    @cInclude("kernel_engine/common/error.h");
    @cInclude("kernel_engine/ecs/ecs.h");
    @cInclude("kernel_engine/runtime/runtime.h");
    @cInclude("kernel_engine/runtime/system_ctx.h");
    @cInclude("kernel_engine/render/gpu/gpu_device.h");
    @cInclude("kernel_engine/render/gpu/gpu_commands.h");
    @cInclude("kernel_engine/render/service/render_service.h");
    @cInclude("kernel_engine/render/service/pass_context.h");
    @cInclude("kernel_engine/render/ui/ui_create.h");
});
