//! The shader layout of a pass that draws meshes with their materials: the shader's loose
//! parameters, the material block the binder binds per material, and the per-draw object block.

/// The layout of one compiled material shader for the C namespace `c`, its object block hinted to
/// take a dynamic offset per draw.
pub fn MaterialPassGroups(comptime c: type) type {
    return struct {
        const Self = @This();

        const object_hint = [_]c.ke_render_binding_hint{.{ .name = "object", .flags = c.KE_RENDER_BINDING_HINT_DYNAMIC_OFFSET }};

        binder: *c.ke_render_resource_binder = undefined,
        layout: c.ke_render_shader_layout = c.KE_RENDER_BINDING_INVALID,

        /// Builds the layout of the shader compiled as `shader`, whose stages are vertex and
        /// fragment. On failure it returns false with the binder's error.
        pub fn init(self: *Self, binder: *c.ke_render_resource_binder, shader: [*c]const u8, out_error: [*c][*c]c.ke_error) bool {
            self.binder = binder;
            self.layout = binder.create_shader_layout.?(binder, &c.ke_render_shader_layout_params{
                .shader = shader,
                .stages = c.KE_GPU_SHADER_STAGE_VERTEX | c.KE_GPU_SHADER_STAGE_FRAGMENT,
                .hints = &object_hint,
                .hint_count = object_hint.len,
            }, out_error);
            return self.layout != c.KE_RENDER_BINDING_INVALID;
        }

        /// Fills the bind group layouts of `pp` with the ones the shader's pipeline declares.
        pub fn place(self: *const Self, pp: *c.ke_gpu_render_pipeline_params, out_error: [*c][*c]c.ke_error) bool {
            return self.binder.pipeline_layouts.?(self.binder, self.layout, &pp.bind_group_layouts, pp.bind_group_layouts.len, &pp.bind_group_layout_count, out_error);
        }

        /// Makes `material` the one the next draws of `pass` read.
        pub fn bindMaterial(self: *const Self, pass: [*c]c.ke_gpu_render_pass, material: c.ke_render_material_binding) void {
            self.binder.bind_material.?(self.binder, pass, self.layout, material);
        }

        /// Destroys the layout, if one was built.
        pub fn release(self: *Self) void {
            if (self.layout != c.KE_RENDER_BINDING_INVALID) self.binder.destroy_shader_layout.?(self.binder, self.layout);
            self.layout = c.KE_RENDER_BINDING_INVALID;
        }
    };
}
