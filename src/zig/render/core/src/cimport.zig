// Single shared @cImport for every render-core Zig file. Two separate
// @cImport blocks produce distinct (incompatible) Zig types for the same C
// struct, even when textually identical — every file that needs to pass
// these types across a module boundary (e.g. render_module.zig handing a
// *ke_render_core to shadow_module.zig) must import this same `c`, never
// re-@cInclude its own copy.
pub const c = @cImport({
    @cInclude("kernel_engine/runtime/runtime.h");
    @cInclude("kernel_engine/runtime/system_ctx.h");
    @cInclude("kernel_engine/ecs/ke_ecs.h");
    @cInclude("kernel_engine/spatial/transform.h");
    @cInclude("kernel_engine/render/components.h");
    @cInclude("kernel_engine/render/gpu_device.h");
    @cInclude("kernel_engine/render/gpu_commands.h");
    @cInclude("kernel_engine/render/core/render_core.h");
    @cInclude("kernel_engine/render/core/pass_context.h");
    @cInclude("kernel_engine/render/core/render_core_create.h");
    @cInclude("kernel_engine/render/core/render_module_create.h");
    @cInclude("kernel_engine/render/tonemap/tonemap_create.h");
    @cInclude("kernel_engine/render/skybox/skybox_create.h");
    @cInclude("kernel_engine/render/ui/ui_create.h");
    @cInclude("kernel_engine/render/gbuffer/gbuffer_create.h");
    @cInclude("kernel_engine/logger/logger.h");
});
