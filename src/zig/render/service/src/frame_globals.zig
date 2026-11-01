//! The parameters every shader shares and the service provides itself: the frame globals, the
//! scene's light and the common samplers, kept on the CPU for the passes and uploaded for the GPU.

const abi_asset_resolver = @import("abi_asset_resolver");
const abi_render_gpu = @import("abi_render_gpu");
const std = @import("std");
const rc = @import("render_service.zig");
const abi_render = @import("abi_render");
const R = rc.R;
const frame_lifecycle = @import("frame_lifecycle.zig");

/// The largest anisotropy WebGPU accepts, which the anisotropic sampler asks for.
const max_anisotropy: u16 = 16;

const Sampler = struct {
    name: [:0]const u8,
    min_mag: abi_render_gpu.c.ke_gpu_filter,
    mipmap: abi_render_gpu.c.ke_gpu_sampler_mipmap_filter,
    address: abi_render_gpu.c.ke_gpu_address_mode,
    anisotropy: u16,
};

const samplers = [_]Sampler{
    .{ .name = "ke_samp_linear", .min_mag = abi_render_gpu.c.KE_GPU_FILTER_LINEAR, .mipmap = abi_render_gpu.c.KE_GPU_SAMPLER_MIPMAP_LINEAR, .address = abi_render_gpu.c.KE_GPU_ADDRESS_MODE_REPEAT, .anisotropy = 1 },
    .{ .name = "ke_samp_nearest", .min_mag = abi_render_gpu.c.KE_GPU_FILTER_NEAREST, .mipmap = abi_render_gpu.c.KE_GPU_SAMPLER_MIPMAP_NEAREST, .address = abi_render_gpu.c.KE_GPU_ADDRESS_MODE_REPEAT, .anisotropy = 1 },
    .{ .name = "ke_samp_aniso", .min_mag = abi_render_gpu.c.KE_GPU_FILTER_LINEAR, .mipmap = abi_render_gpu.c.KE_GPU_SAMPLER_MIPMAP_LINEAR, .address = abi_render_gpu.c.KE_GPU_ADDRESS_MODE_REPEAT, .anisotropy = max_anisotropy },
    .{ .name = "ke_samp_shadow", .min_mag = abi_render_gpu.c.KE_GPU_FILTER_LINEAR, .mipmap = abi_render_gpu.c.KE_GPU_SAMPLER_MIPMAP_NEAREST, .address = abi_render_gpu.c.KE_GPU_ADDRESS_MODE_CLAMP_TO_EDGE, .anisotropy = 1 },
    .{ .name = "ke_samp_point_clamp", .min_mag = abi_render_gpu.c.KE_GPU_FILTER_NEAREST, .mipmap = abi_render_gpu.c.KE_GPU_SAMPLER_MIPMAP_NEAREST, .address = abi_render_gpu.c.KE_GPU_ADDRESS_MODE_CLAMP_TO_EDGE, .anisotropy = 1 },
};

/// What the service holds for the shared parameters: the CPU copies the passes read, the uniform
/// buffers the shaders read and one sampler per entry of `samplers`.
pub const Globals = struct {
    frame: abi_render.c.ke_render_frame_globals = std.mem.zeroes(abi_render.c.ke_render_frame_globals),
    lighting: abi_render.c.ke_render_lighting = std.mem.zeroes(abi_render.c.ke_render_lighting),
    frame_buffer: abi_asset_resolver.c.ke_gpu_buffer = abi_render_gpu.c.KE_GPU_INVALID_HANDLE,
    lighting_buffer: abi_asset_resolver.c.ke_gpu_buffer = abi_render_gpu.c.KE_GPU_INVALID_HANDLE,
    samplers: [samplers.len]abi_asset_resolver.c.ke_gpu_sampler = [_]abi_asset_resolver.c.ke_gpu_sampler{abi_render_gpu.c.KE_GPU_INVALID_HANDLE} ** samplers.len,

    /// Creates the buffers and the samplers. On failure it fails with the device's code, and what
    /// it created stays for `release`.
    pub fn create(self: *Globals, dev: *abi_render_gpu.c.ke_gpu_device) R.Error!void {
        try uniformBuffer(dev, "service.ke_frame", @sizeOf(abi_render.c.ke_render_frame_globals), &self.frame_buffer);
        try uniformBuffer(dev, "service.ke_lighting", @sizeOf(abi_render.c.ke_render_lighting), &self.lighting_buffer);
        for (samplers, &self.samplers) |s, *out| {
            try R.check(dev.create_sampler.?(dev, &abi_render_gpu.c.ke_gpu_sampler_params{
                .label = s.name.ptr,
                .min_filter = s.min_mag,
                .mag_filter = s.min_mag,
                .mipmap_filter = s.mipmap,
                .address_mode_u = s.address,
                .address_mode_v = s.address,
                .address_mode_w = s.address,
                .lod_min_clamp = 0.0,
                .lod_max_clamp = 1.0,
                .compare = abi_render_gpu.c.KE_GPU_COMPARE_UNDEFINED,
                .max_anisotropy = s.anisotropy,
            }, out));
        }
    }

    /// Destroys every buffer and sampler that was created.
    pub fn release(self: *Globals, dev: *abi_render_gpu.c.ke_gpu_device) void {
        for (self.samplers) |s| {
            if (s != abi_render_gpu.c.KE_GPU_INVALID_HANDLE) dev.destroy_sampler.?(dev, s);
        }
        if (self.lighting_buffer != abi_render_gpu.c.KE_GPU_INVALID_HANDLE) dev.destroy_buffer.?(dev, self.lighting_buffer);
        if (self.frame_buffer != abi_render_gpu.c.KE_GPU_INVALID_HANDLE) dev.destroy_buffer.?(dev, self.frame_buffer);
    }

    /// Gives `binder` every shared parameter by its name. On failure it fails with the binder's
    /// code.
    pub fn provideTo(self: *const Globals, binder: *abi_render_gpu.c.ke_render_resource_binder) R.Error!void {
        const names = [_][:0]const u8{ "ke_frame", "ke_lighting" };
        for (names) |name| {
            const b = self.binding(name).?;
            try R.check(binder.provide.?(binder, &b));
        }
        for (samplers) |s| {
            const b = self.binding(s.name).?;
            try R.check(binder.provide.?(binder, &b));
        }
    }

    /// The binding of the shared parameter named `name`, or null when the service provides none
    /// by that name.
    pub fn binding(self: *const Globals, name: []const u8) ?abi_render_gpu.c.ke_render_shader_binding {
        var b = std.mem.zeroes(abi_render_gpu.c.ke_render_shader_binding);
        if (std.mem.eql(u8, name, "ke_frame")) {
            b.name = "ke_frame";
            b.buffer = self.frame_buffer;
            b.buffer_size = @sizeOf(abi_render.c.ke_render_frame_globals);
            return b;
        }
        if (std.mem.eql(u8, name, "ke_lighting")) {
            b.name = "ke_lighting";
            b.buffer = self.lighting_buffer;
            b.buffer_size = @sizeOf(abi_render.c.ke_render_lighting);
            return b;
        }
        for (samplers, self.samplers) |s, handle| {
            if (std.mem.eql(u8, name, s.name)) {
                b.name = s.name.ptr;
                b.sampler = handle;
                return b;
            }
        }
        return null;
    }
};

fn uniformBuffer(dev: *abi_render_gpu.c.ke_gpu_device, label: [*c]const u8, size: usize, out: *abi_asset_resolver.c.ke_gpu_buffer) R.Error!void {
    try R.check(dev.create_buffer.?(dev, &abi_render_gpu.c.ke_gpu_buffer_params{
        .label = label,
        .initial_data = null,
        .size = size,
        .usage = abi_render_gpu.c.KE_GPU_BUFFER_USAGE_UNIFORM | abi_render_gpu.c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = false,
    }, out));
}

/// The service's `set_frame_globals` slot: keeps the copy and records its upload for this frame. A
/// null argument is ignored.
pub fn setFrameGlobals(self: [*c]abi_render.c.ke_render_service, globals: [*c]const abi_render.c.ke_render_frame_globals) callconv(.c) void {
    if (self == null or globals == null) return;
    const st = rc.coreOf(self);
    st.globals.frame = globals.*;
    frame_lifecycle.uploadBuffer(self, st.globals.frame_buffer, 0, &st.globals.frame, @sizeOf(abi_render.c.ke_render_frame_globals));
}

/// The service's `frame_globals` slot.
pub fn frameGlobals(self: [*c]abi_render.c.ke_render_service) callconv(.c) [*c]const abi_render.c.ke_render_frame_globals {
    if (self == null) return null;
    return &rc.coreOf(self).globals.frame;
}

/// The service's `set_lighting` slot: keeps the copy and records its upload for this frame. A null
/// argument is ignored.
pub fn setLighting(self: [*c]abi_render.c.ke_render_service, lighting: [*c]const abi_render.c.ke_render_lighting) callconv(.c) void {
    if (self == null or lighting == null) return;
    const st = rc.coreOf(self);
    st.globals.lighting = lighting.*;
    frame_lifecycle.uploadBuffer(self, st.globals.lighting_buffer, 0, &st.globals.lighting, @sizeOf(abi_render.c.ke_render_lighting));
}

/// The service's `lighting` slot.
pub fn lightingOf(self: [*c]abi_render.c.ke_render_service) callconv(.c) [*c]const abi_render.c.ke_render_lighting {
    if (self == null) return null;
    return &rc.coreOf(self).globals.lighting;
}
