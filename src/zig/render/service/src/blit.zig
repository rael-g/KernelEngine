//! Draws one resource into another, so a pass's first color write can start as a resource it reads.

const abi_asset_resolver = @import("abi_asset_resolver");
const abi_render_gpu = @import("abi_render_gpu");
const std = @import("std");
const rc = @import("render_service.zig");
const FrameLog = @import("frame_log.zig").FrameLog;
const abi_render = @import("abi_render");
const R = rc.R;

const layout_params = abi_render_gpu.c.ke_render_shader_layout_params{
    .shader = "blit",
    .stages = abi_render_gpu.c.KE_GPU_SHADER_STAGE_FRAGMENT,
    .hints = null,
    .hint_count = 0,
};

/// The shaders and layout of the full-screen draw, made once when the service is created, and the
/// sets the frame's draws made. A set must outlive the submission of the frame that binds it, so the
/// sets of a frame are released when the next one begins; `sets` is a frame log because the passes
/// of one wave open their render passes concurrently. It starts with no slots and grows to the
/// draws a frame makes.
pub const Blit = struct {
    layout: abi_asset_resolver.c.ke_render_shader_layout = abi_render_gpu.c.KE_RENDER_BINDING_INVALID,
    pipeline: abi_render_gpu.c.ke_gpu_render_pipeline_params = undefined,
    sets: FrameLog(abi_asset_resolver.c.ke_render_resource_set) = .{ .items = &.{}, .blank = abi_render_gpu.c.KE_RENDER_BINDING_INVALID },

    /// Loads the "blit" shaders and creates their layout. When either fails nothing is left to
    /// release.
    pub fn prepare(self: *Blit, service: [*c]abi_render.c.ke_render_service, binder: *abi_render_gpu.c.ke_render_resource_binder) R.Error!void {
        var vs: abi_asset_resolver.c.ke_gpu_shader_module = undefined;
        try R.check(service.*.load_shader.?(service, "blit", abi_render_gpu.c.KE_GPU_SHADER_STAGE_VERTEX, &vs));
        var fs: abi_asset_resolver.c.ke_gpu_shader_module = undefined;
        try R.check(service.*.load_shader.?(service, "blit", abi_render_gpu.c.KE_GPU_SHADER_STAGE_FRAGMENT, &fs));
        var layout: abi_asset_resolver.c.ke_render_shader_layout = undefined;
        try R.check(binder.create_shader_layout.?(binder, &layout_params, &layout));
        errdefer binder.destroy_shader_layout.?(binder, layout);

        var pp = std.mem.zeroes(abi_render_gpu.c.ke_gpu_render_pipeline_params);
        pp.label = "blit.pipeline";
        pp.vertex_module = vs;
        pp.vertex_entry = "vs_main";
        pp.fragment_module = fs;
        pp.fragment_entry = "fs_main";
        try R.check(binder.pipeline_layouts.?(binder, layout, &pp.bind_group_layouts, pp.bind_group_layouts.len, &pp.bind_group_layout_count));
        pp.color_target_count = 1;
        pp.blend_state.write_mask = 0x0F;
        pp.depth_stencil.depth_compare = abi_render_gpu.c.KE_GPU_COMPARE_ALWAYS;
        self.layout = layout;
        self.pipeline = pp;
    }

    /// Releases the sets of the frame that just ended. Called by `beginFrame`, before any pass of
    /// the new frame runs.
    pub fn releaseSets(self: *Blit, binder: *abi_render_gpu.c.ke_render_resource_binder) void {
        self.sets.seal();
        var it = self.sets.iterator();
        while (it.next()) |set| {
            if (set.* != abi_render_gpu.c.KE_RENDER_BINDING_INVALID) binder.destroy_set.?(binder, set.*);
        }
        self.sets.reset(null);
    }

    /// Releases the sets still held and the layout.
    pub fn release(self: *Blit, binder: *abi_render_gpu.c.ke_render_resource_binder) void {
        self.releaseSets(binder);
        self.sets.deinit(null);
        if (self.layout == abi_render_gpu.c.KE_RENDER_BINDING_INVALID) return;
        binder.destroy_shader_layout.?(binder, self.layout);
        self.layout = abi_render_gpu.c.KE_RENDER_BINDING_INVALID;
    }

    /// Records on `encoder` a render pass that draws `src` over the whole of `dst`, whose format is
    /// `dst_format`. False, recording nothing, when no entry of the log or no set can be made.
    pub fn draw(self: *Blit, service: [*c]abi_render.c.ke_render_service, binder: *abi_render_gpu.c.ke_render_resource_binder, encoder: *abi_render_gpu.c.ke_gpu_command_encoder, src: abi_asset_resolver.c.ke_gpu_texture_view, dst: abi_asset_resolver.c.ke_gpu_texture_view, dst_format: abi_render_gpu.c.ke_gpu_texture_format) bool {
        const slot = self.sets.claim() orelse return false;
        const bindings = [1]abi_render_gpu.c.ke_render_shader_binding{
            .{ .name = "t_src", .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = src, .sampler = 0 },
        };
        var set: abi_asset_resolver.c.ke_render_resource_set = abi_render_gpu.c.KE_RENDER_BINDING_INVALID;
        const made = binder.create_set.?(binder, self.layout, null, "blit.set", &bindings, bindings.len, &set);
        slot.* = set;
        if (made != R.ok) return false;

        var pp = self.pipeline;
        pp.color_target_formats[0] = dst_format;
        const color = [1]abi_render_gpu.c.ke_gpu_color_attachment{.{
            .view = dst,
            .load_op = abi_render_gpu.c.KE_GPU_LOAD_OP_CLEAR,
            .store_op = abi_render_gpu.c.KE_GPU_STORE_OP_STORE,
            .clear_value = .{ .color = .{ 0, 0, 0, 0 } },
        }};
        const params = abi_render_gpu.c.ke_gpu_render_pass_params{
            .label = "blit",
            .color_attachments = &color,
            .color_attachment_count = 1,
            .depth_stencil_attachment = null,
        };
        const rp = encoder.begin_render_pass.?(encoder, &params);
        rp.?.set_pipeline.?(rp, service.*.get_or_create_pipeline.?(service, &pp));
        binder.bind_render_set.?(binder, rp, set, null, 0);
        rp.?.draw.?(rp, 3, 1, 0, 0);
        rp.?.end.?(rp);
        return true;
    }
};
