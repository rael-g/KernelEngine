
const cimport = @import("cimport.zig");
const c = cimport.c;

const std = @import("std");

const Vertex = extern struct {
    position: [3]f32,
    normal: [3]f32,
    uv: [2]f32,
    tangent: [3]f32,
};

pub const State = struct {
    core: *c.ke_render_service,
    mesh_cid: c.ke_component_id,
    /// Borrowed, optional: turns an authored path into an uploaded texture. Null
    /// where the host wired no loader, and a sprite naming a file then draws
    /// untextured rather than failing a frame.
    resolver: ?*c.ke_asset_resolver,
};

fn quadFor(core: *c.ke_render_service, sp: *const c.ke_sprite2d_component) c.ke_mesh_handle {
    const w = sp.size.x;
    const h = sp.size.y;
    const x0 = -sp.pivot.x * w;
    const x1 = x0 + w;
    const y0 = -sp.pivot.y * h;
    const y1 = y0 + h;

    var uv_x0 = sp.region.x;
    var uv_x1 = sp.region.x + sp.region.z;
    var uv_y0 = sp.region.y + sp.region.w;
    var uv_y1 = sp.region.y;
    if (sp.flip_h != 0) std.mem.swap(f32, &uv_x0, &uv_x1);
    if (sp.flip_v != 0) std.mem.swap(f32, &uv_y0, &uv_y1);

    const n = [3]f32{ 0, 0, 1 };
    const t = [3]f32{ 1, 0, 0 };
    const verts = [4]Vertex{
        .{ .position = .{ x0, y0, 0 }, .normal = n, .uv = .{ uv_x0, uv_y0 }, .tangent = t },
        .{ .position = .{ x1, y0, 0 }, .normal = n, .uv = .{ uv_x1, uv_y0 }, .tangent = t },
        .{ .position = .{ x1, y1, 0 }, .normal = n, .uv = .{ uv_x1, uv_y1 }, .tangent = t },
        .{ .position = .{ x0, y1, 0 }, .normal = n, .uv = .{ uv_x0, uv_y1 }, .tangent = t },
    };
    const idx = [6]u16{ 0, 1, 2, 0, 2, 3 };

    var key_buf: [192]u8 = undefined;
    const key = std.fmt.bufPrintZ(&key_buf, "sprite:{d}:{d}:{d}:{d}:{d}:{d}:{d}:{d}:{d}:{d}", .{
        w,          h,          sp.pivot.x,  sp.pivot.y, sp.region.x,
        sp.region.y, sp.region.z, sp.region.w, sp.flip_h,  sp.flip_v,
    }) catch return c.KE_MESH_NONE;

    return core.upload_mesh.?(core, key.ptr, &verts, @sizeOf(@TypeOf(verts)), &idx, idx.len, null);
}

/// Uploads the image the sprite names, once.
fn resolveTexture(st: *State, sp: *c.ke_sprite2d_component) c.ke_texture_handle {
    if (sp.texture[0] == 0) return c.KE_TEXTURE_NONE;
    if (c.ke_texture_is_valid(sp.texture_handle)) return sp.texture_handle;

    const resolver = st.resolver orelse return c.KE_TEXTURE_NONE;
    sp.texture_handle = resolver.resolve_texture_into.?(resolver, st.core, &sp.texture, null);
    return sp.texture_handle;
}

fn materialFor(st: *State, sp: *c.ke_sprite2d_component) c.ke_material_handle {
    const core = st.core;
    const col = sp.color;
    const tex = resolveTexture(st, sp);
    var key_buf: [192]u8 = undefined;
    const key = std.fmt.bufPrintZ(&key_buf, "sprite:{d}:{d}:{d}:{d}:{d}:{d}:{d}", .{
        col.x, col.y, col.z, col.w, tex.bits, sp.alpha_mode, sp.alpha_cutoff,
    }) catch return c.KE_MATERIAL_NONE;

    return core.create_material.?(
        core,
        key.ptr,
        @ptrCast(&sp.color),
        0,
        1,
        tex,
        c.KE_TEXTURE_NONE,
        sp.alpha_mode,
        sp.alpha_cutoff,
        1.5,
        0,
        null,
        null,
    );
}

pub fn system(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) void {
    const st: *State = @alignCast(@ptrCast(user.?));

    var segc: usize = 0;
    var segs = c.ke_system_ctx_view(ctx, 0, &segc);
    var s: usize = 0;
    while (s < segc) : (s += 1) {
        const sprites: [*c]c.ke_sprite2d_component = @ptrCast(@alignCast(segs[s].columns[0]));
        const meshes: [*c]c.ke_mesh_component = @ptrCast(@alignCast(segs[s].columns[1]));
        var i: usize = 0;
        while (i < segs[s].count) : (i += 1) {
            const sp: *c.ke_sprite2d_component = @ptrCast(&sprites[i]);
            sp.attached = 1;
            meshes[i].mesh = quadFor(st.core, sp);
            meshes[i].material = materialFor(st, sp);
        }
    }

    segs = c.ke_system_ctx_view(ctx, 1, &segc);
    s = 0;
    while (s < segc) : (s += 1) {
        const sprites: [*c]c.ke_sprite2d_component = @ptrCast(@alignCast(segs[s].columns[0]));
        var i: usize = 0;
        while (i < segs[s].count) : (i += 1) {
            if (sprites[i].attached != 0) continue;
            sprites[i].attached = 1;
            _ = c.ke_system_ctx_attach(ctx, segs[s].entities[i], st.mesh_cid, null, 0);
        }
    }
}
