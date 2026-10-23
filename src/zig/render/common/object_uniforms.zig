//! The per-draw uniform buffer of a pass, one slot of `stride` bytes per draw reached by a dynamic
//! offset, grown to the number of draws a frame asks for.

/// The buffer, its resource set and the number of slots they hold, for the C namespace `c` and one
/// draw record `Record`. The set binds the buffer to the `object` block of the shader `layout`
/// was built for, which hints that block to take a dynamic offset. `ensure` makes room before a
/// frame uploads; the handles change only there.
pub fn ObjectUniforms(comptime c: type, comptime Record: type) type {
    return struct {
        const Self = @This();

        /// The distance between slots: the smallest uniform offset alignment WebGPU guarantees.
        pub const stride: u32 = 256;

        device: *c.ke_gpu_device,
        binder: *c.ke_render_resource_binder,
        layout: c.ke_render_shader_layout,
        buffer_label: [*c]const u8,
        set_label: [*c]const u8,
        buffer: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
        set: c.ke_render_resource_set = c.KE_RENDER_BINDING_INVALID,
        capacity: u32 = 0,

        /// Makes room for `count` draws, replacing the buffer and the set with ones of the next
        /// power of two slots when the current ones are smaller. On failure it returns the
        /// device's or the binder's code and keeps what it had.
        pub fn ensure(self: *Self, count: u32) c.ke_result {
            if (count <= self.capacity) return c.KE_OK;
            const slots = @import("std").math.ceilPowerOfTwoAssert(u32, @max(count, 1));
            const dev = self.device;
            var buffer: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE;
            const made = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
                .label = self.buffer_label,
                .initial_data = null,
                .size = @as(u64, stride) * slots,
                .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST,
                .mapped_at_creation = false,
            }, &buffer);
            if (made != c.KE_OK) return made;
            const binding = [_]c.ke_render_shader_binding{.{
                .name = "object",
                .buffer = buffer,
                .buffer_offset = 0,
                .buffer_size = @sizeOf(Record),
                .texture_view = 0,
                .sampler = 0,
            }};
            var set: c.ke_render_resource_set = c.KE_RENDER_BINDING_INVALID;
            const bound = self.binder.create_set.?(self.binder, self.layout, "object", self.set_label, &binding, binding.len, &set);
            if (bound != c.KE_OK) {
                dev.destroy_buffer.?(dev, buffer);
                return bound;
            }
            self.release();
            self.buffer = buffer;
            self.set = set;
            self.capacity = slots;
            return c.KE_OK;
        }

        /// The dynamic offset of a draw's slot.
        pub fn offset(index: u32) u32 {
            return index * stride;
        }

        /// Makes the slot of draw `index` the object the next draws of `pass` read.
        pub fn bind(self: *const Self, pass: [*c]c.ke_gpu_render_pass, index: u32) void {
            const at = [_]u32{offset(index)};
            self.binder.bind_render_set.?(self.binder, pass, self.set, &at, at.len);
        }

        /// Destroys the buffer and the set it holds, if any.
        pub fn release(self: *Self) void {
            const dev = self.device;
            if (self.set != c.KE_RENDER_BINDING_INVALID) self.binder.destroy_set.?(self.binder, self.set);
            if (self.buffer != c.KE_GPU_INVALID_HANDLE) dev.destroy_buffer.?(dev, self.buffer);
            self.set = c.KE_RENDER_BINDING_INVALID;
            self.buffer = c.KE_GPU_INVALID_HANDLE;
            self.capacity = 0;
        }
    };
}
