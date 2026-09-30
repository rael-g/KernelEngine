pub const c = @cImport({
    @cInclude("kernel_engine/ecs/ke_ecs.h");
    @cInclude("kernel_engine/audio/components.h");
    @cInclude("kernel_engine/audio/component_fields.h");
    @cInclude("kernel_engine/framework/world.h");
    @cInclude("kernel_engine/audio/module/audio_module.h");
});
