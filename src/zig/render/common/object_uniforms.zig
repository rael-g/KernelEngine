//! The per-draw uniform buffer of a pass, one slot of `stride` bytes per draw reached by a dynamic
//! offset, grown to the number of draws a frame asks for.

/// The buffer, its bind group and the number of slots they hold, for the C namespace `c` and one
/// draw record `Record`. The bind group binds the buffer to the shader's `object` block of the
/// group `group` names. `ensure` makes room before a frame uploads; the handles change only there.
pub fn ObjectUniforms(comptime c: type, comptime Record: type) type {
    return struct {
        const Self = @This();

        /// The distance between slots: the smallest uniform offset alignment WebGPU guarantees.
        pub const stride: u32 = 256;

        device: *c.ke_gpu_device,
        core: *c.ke_render_service,
        group: *const c.ke_render_shader_group_params,
        layout: c.ke_gpu_bind_group_layout,
        buffer_label: [*c]const u8,
        bind_group_label: [*c]const u8,
        buffer: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
        bind_group: c.ke_gpu_bind_group = c.KE_GPU_INVALID_HANDLE,
        capacity: u32 = 0,

        /// Makes room for `count` draws, replacing the buffer and the bind group with ones of the
        /// next power of two slots when the current ones are smaller. On failure it returns false
        /// with the device's error and keeps what it had.
        pub fn ensure(self: *Self, count: u32, out_error: [*c][*c]c.ke_error) bool {
            if (count <= self.capacity) return true;
            const slots = @import("std").math.ceilPowerOfTwoAssert(u32, @max(count, 1));
            const dev = self.device;
            const buffer = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
                .label = self.buffer_label,
                .initial_data = null,
                .size = @as(u64, stride) * slots,
                .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST,
                .mapped_at_creation = 0,
            }, out_error);
            if (buffer == c.KE_GPU_INVALID_HANDLE) return false;
            const binding = [_]c.ke_render_shader_binding{.{
                .name = "object",
                .buffer = buffer,
                .buffer_offset = 0,
                .buffer_size = @sizeOf(Record),
                .texture_view = 0,
                .sampler = 0,
            }};
            const bind_group = self.core.*.create_shader_bind_group.?(self.core, self.group, self.layout, self.bind_group_label, &binding, binding.len, out_error);
            if (bind_group == c.KE_GPU_INVALID_HANDLE) {
                dev.destroy_buffer.?(dev, buffer);
                return false;
            }
            self.release();
            self.buffer = buffer;
            self.bind_group = bind_group;
            self.capacity = slots;
            return true;
        }

        /// The dynamic offset of a draw's slot.
        pub fn offset(index: u32) u32 {
            return index * stride;
        }

        /// Destroys the buffer and the bind group it holds, if any.
        pub fn release(self: *Self) void {
            const dev = self.device;
            if (self.bind_group != c.KE_GPU_INVALID_HANDLE) dev.destroy_bind_group.?(dev, self.bind_group);
            if (self.buffer != c.KE_GPU_INVALID_HANDLE) dev.destroy_buffer.?(dev, self.buffer);
            self.bind_group = c.KE_GPU_INVALID_HANDLE;
            self.buffer = c.KE_GPU_INVALID_HANDLE;
            self.capacity = 0;
        }
    };
}
