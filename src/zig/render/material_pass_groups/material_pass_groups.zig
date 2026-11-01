//! The shader layout of a pass that draws meshes with their materials: the shader's loose
//! parameters, the material block the binder binds per material, and the per-draw object block.

const abi_asset_resolver = @import("abi_asset_resolver");
const abi_render_gpu = @import("abi_render_gpu");
const abi_render = @import("abi_render");
const abi_result = @import("abi_result");
const Self = @This();

const object_hint = [_]abi_render_gpu.c.ke_render_binding_hint{.{ .name = "object", .flags = abi_render_gpu.c.KE_RENDER_BINDING_HINT_DYNAMIC_OFFSET }};

binder: *abi_render_gpu.c.ke_render_resource_binder = undefined,
layout: abi_asset_resolver.c.ke_render_shader_layout = abi_render_gpu.c.KE_RENDER_BINDING_INVALID,

/// Builds the layout of the shader compiled as `shader`, whose stages are vertex and
/// fragment. On failure it returns the binder's code.
pub fn init(self: *Self, binder: *abi_render_gpu.c.ke_render_resource_binder, shader: [*c]const u8) abi_result.c.ke_result {
    self.binder = binder;
    return binder.create_shader_layout.?(binder, &abi_render_gpu.c.ke_render_shader_layout_params{
        .shader = shader,
        .stages = abi_render_gpu.c.KE_GPU_SHADER_STAGE_VERTEX | abi_render_gpu.c.KE_GPU_SHADER_STAGE_FRAGMENT,
        .hints = &object_hint,
        .hint_count = object_hint.len,
    }, &self.layout);
}

/// Fills the bind group layouts of `pp` with the ones the shader's pipeline declares; on
/// failure it returns the binder's code.
pub fn place(self: *const Self, pp: *abi_render_gpu.c.ke_gpu_render_pipeline_params) abi_result.c.ke_result {
    return self.binder.pipeline_layouts.?(self.binder, self.layout, &pp.bind_group_layouts, pp.bind_group_layouts.len, &pp.bind_group_layout_count);
}

/// Makes `material` the one the next draws of `pass` read.
pub fn bindMaterial(self: *const Self, pass: [*c]abi_render_gpu.c.ke_gpu_render_pass, material: abi_asset_resolver.c.ke_render_material_binding) void {
    self.binder.bind_material.?(self.binder, pass, self.layout, material);
}

/// Destroys the layout, if one was built.
pub fn release(self: *Self) void {
    if (self.layout != abi_render_gpu.c.KE_RENDER_BINDING_INVALID) self.binder.destroy_shader_layout.?(self.binder, self.layout);
    self.layout = abi_render_gpu.c.KE_RENDER_BINDING_INVALID;
}
