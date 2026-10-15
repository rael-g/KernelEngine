//! The bind groups of a pass that draws meshes with their materials: the shader's loose
//! parameters, the material block the service binds per material, and the per-draw object block.

/// The groups of the C namespace `c`, read from the reflection of one compiled material shader.
/// It holds the group params it was read with, which `ObjectUniforms` keeps a pointer to, so it
/// must not move after `init`.
pub fn MaterialPassGroups(comptime c: type) type {
    return struct {
        const Self = @This();

        const object_hint = [_]c.ke_render_binding_hint{.{ .name = "object", .flags = c.KE_RENDER_BINDING_HINT_DYNAMIC_OFFSET }};

        frame_params: c.ke_render_shader_group_params = undefined,
        object_params: c.ke_render_shader_group_params = undefined,
        frame: c.ke_render_shader_group = .{ .layout = c.KE_GPU_INVALID_HANDLE, .index = 0 },
        object: c.ke_render_shader_group = .{ .layout = c.KE_GPU_INVALID_HANDLE, .index = 0 },
        material_index: u32 = 0,

        /// Reads the groups of the shader compiled as `shader`, whose stages are vertex and
        /// fragment. On failure it returns false with the service's error, and what it created
        /// stays for `release`.
        pub fn init(self: *Self, core: *c.ke_render_service, dev: *c.ke_gpu_device, shader: [*c]const u8, out_error: [*c][*c]c.ke_error) bool {
            const stages = c.KE_GPU_SHADER_STAGE_VERTEX | c.KE_GPU_SHADER_STAGE_FRAGMENT;
            self.frame_params = .{ .shader = shader, .stages = stages, .block = null, .hints = null, .hint_count = 0 };
            self.object_params = .{ .shader = shader, .stages = stages, .block = "object", .hints = &object_hint, .hint_count = object_hint.len };
            if (!core.*.shader_group_layout.?(core, &self.frame_params, &self.frame, out_error)) return false;
            if (!core.*.shader_group_layout.?(core, &self.object_params, &self.object, out_error)) return false;
            const material_params = c.ke_render_shader_group_params{ .shader = shader, .stages = stages, .block = "mat", .hints = null, .hint_count = 0 };
            var material: c.ke_render_shader_group = undefined;
            if (!core.*.shader_group_layout.?(core, &material_params, &material, out_error)) return false;
            dev.destroy_bind_group_layout.?(dev, material.layout);
            self.material_index = material.index;
            return true;
        }

        /// Places the three layouts in `pp` at the indices the shader expects them at; the
        /// material's is the layout the service builds every material's bind group from.
        pub fn place(self: *const Self, core: *c.ke_render_service, pp: *c.ke_gpu_render_pipeline_params) void {
            pp.bind_group_layouts[self.frame.index] = self.frame.layout;
            pp.bind_group_layouts[self.material_index] = core.*.material_layout.?(core);
            pp.bind_group_layouts[self.object.index] = self.object.layout;
            pp.bind_group_layout_count = @max(self.frame.index, @max(self.material_index, self.object.index)) + 1;
        }

        /// Destroys the layouts that were created.
        pub fn release(self: *Self, dev: *c.ke_gpu_device) void {
            if (self.object.layout != c.KE_GPU_INVALID_HANDLE) dev.destroy_bind_group_layout.?(dev, self.object.layout);
            if (self.frame.layout != c.KE_GPU_INVALID_HANDLE) dev.destroy_bind_group_layout.?(dev, self.frame.layout);
            self.object.layout = c.KE_GPU_INVALID_HANDLE;
            self.frame.layout = c.KE_GPU_INVALID_HANDLE;
        }
    };
}
