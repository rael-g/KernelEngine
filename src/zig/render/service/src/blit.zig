//! Draws one resource into another, so a pass's first color write can start as a resource it reads.

const std = @import("std");
const rc = @import("render_service.zig");
const FrameLog = @import("frame_log.zig").FrameLog;
const c = rc.c;

const layout_params = c.ke_render_shader_layout_params{
    .shader = "blit",
    .stages = c.KE_GPU_SHADER_STAGE_FRAGMENT,
    .hints = null,
    .hint_count = 0,
};

/// The shaders and layout of the full-screen draw, made once when the service is created, and the
/// sets the frame's draws made. A set must outlive the submission of the frame that binds it, so the
/// sets of a frame are released when the next one begins; `sets` is a frame log because the passes
/// of one wave open their render passes concurrently. It starts with no slots and grows to the
/// draws a frame makes.
pub const Blit = struct {
    layout: c.ke_render_shader_layout = c.KE_RENDER_BINDING_INVALID,
    pipeline: c.ke_gpu_render_pipeline_params = undefined,
    sets: FrameLog(c.ke_render_resource_set) = .{ .items = &.{}, .blank = c.KE_RENDER_BINDING_INVALID },

    /// Loads the "blit" shaders and creates their layout. False with the error set when either
    /// fails; nothing is left to release then.
    pub fn prepare(self: *Blit, service: [*c]c.ke_render_service, binder: *c.ke_render_resource_binder, out_error: [*c][*c]c.ke_error) bool {
        const vs = service.*.load_shader.?(service, "blit", c.KE_GPU_SHADER_STAGE_VERTEX, out_error);
        if (vs == c.KE_GPU_INVALID_HANDLE) return false;
        const fs = service.*.load_shader.?(service, "blit", c.KE_GPU_SHADER_STAGE_FRAGMENT, out_error);
        if (fs == c.KE_GPU_INVALID_HANDLE) return false;
        const layout = binder.create_shader_layout.?(binder, &layout_params, out_error);
        if (layout == c.KE_RENDER_BINDING_INVALID) return false;

        var pp = std.mem.zeroes(c.ke_gpu_render_pipeline_params);
        pp.label = "blit.pipeline";
        pp.vertex_module = vs;
        pp.vertex_entry = "vs_main";
        pp.fragment_module = fs;
        pp.fragment_entry = "fs_main";
        if (!binder.pipeline_layouts.?(binder, layout, &pp.bind_group_layouts, pp.bind_group_layouts.len, &pp.bind_group_layout_count, out_error)) {
            binder.destroy_shader_layout.?(binder, layout);
            return false;
        }
        pp.color_target_count = 1;
        pp.blend_state.write_mask = 0x0F;
        pp.depth_stencil.depth_compare = c.KE_GPU_COMPARE_ALWAYS;
        self.layout = layout;
        self.pipeline = pp;
        return true;
    }

    /// Releases the sets of the frame that just ended. Called by `beginFrame`, before any pass of
    /// the new frame runs.
    pub fn releaseSets(self: *Blit, binder: *c.ke_render_resource_binder) void {
        self.sets.seal();
        var it = self.sets.iterator();
        while (it.next()) |set| {
            if (set.* != c.KE_RENDER_BINDING_INVALID) binder.destroy_set.?(binder, set.*);
        }
        self.sets.reset(null);
    }

    /// Releases the sets still held and the layout.
    pub fn release(self: *Blit, binder: *c.ke_render_resource_binder) void {
        self.releaseSets(binder);
        self.sets.deinit(null);
        if (self.layout == c.KE_RENDER_BINDING_INVALID) return;
        binder.destroy_shader_layout.?(binder, self.layout);
        self.layout = c.KE_RENDER_BINDING_INVALID;
    }

    /// Records on `encoder` a render pass that draws `src` over the whole of `dst`, whose format is
    /// `dst_format`. False, recording nothing, when no entry of the log or no set can be made.
    pub fn draw(self: *Blit, service: [*c]c.ke_render_service, binder: *c.ke_render_resource_binder, encoder: *c.ke_gpu_command_encoder, src: c.ke_gpu_texture_view, dst: c.ke_gpu_texture_view, dst_format: c.ke_gpu_texture_format) bool {
        const slot = self.sets.claim() orelse return false;
        const bindings = [1]c.ke_render_shader_binding{
            .{ .name = "t_src", .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = src, .sampler = 0 },
        };
        const set = binder.create_set.?(binder, self.layout, null, "blit.set", &bindings, bindings.len, null);
        slot.* = set;
        if (set == c.KE_RENDER_BINDING_INVALID) return false;

        var pp = self.pipeline;
        pp.color_target_formats[0] = dst_format;
        const color = [1]c.ke_gpu_color_attachment{.{
            .view = dst,
            .load_op = c.KE_GPU_LOAD_OP_CLEAR,
            .store_op = c.KE_GPU_STORE_OP_STORE,
            .clear_value = .{ .color = .{ 0, 0, 0, 0 } },
        }};
        const params = c.ke_gpu_render_pass_params{
            .label = "blit",
            .color_attachments = &color,
            .color_attachment_count = 1,
            .depth_stencil_attachment = null,
        };
        const rp = encoder.begin_render_pass.?(encoder, &params);
        rp.*.set_pipeline.?(rp, service.*.get_or_create_pipeline.?(service, &pp));
        binder.bind_render_set.?(binder, rp, set, null, 0);
        rp.*.draw.?(rp, 3, 1, 0, 0);
        rp.*.end.?(rp);
        return true;
    }
};
