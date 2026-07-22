// Module root for ke_framework.
//
// The framework is mid-migration from C to Zig: Zig drives the build and
// compiles the remaining .c sources into this same DLL (see build.zig), so the
// port can proceed one file at a time with a green build at every step. Files
// already converted are pulled in below — a comptime reference is what makes
// their `export fn` reachable in the DLL's export table. The C files still
// export themselves through the KE_FRAMEWORK_EXPORT macro.
//
// When the last .c is gone, build.zig drops the C sources plus the ke_common /
// allocator_malloc links, and errors move to the shared kerror seam util.

const std = @import("std");

// dlopen'd by a foreign (non-Zig) host (the C# runtime) alongside many other
// plugins in one process. std.Thread's default 256 KiB threadlocal signal
// stack blows the small glibc static-TLS surplus once enough accumulate
// (verified: "cannot allocate memory in static TLS block"); the extra crash-
// handler stack trace it buys isn't worth an unloadable plugin.
pub const std_options: std.Options = .{ .signal_stack_size = null };

comptime {
    _ = @import("components_apply.zig");
    _ = @import("mesh_shape.zig");
    _ = @import("asset_resolver.zig");
    _ = @import("world.zig");
    _ = @import("scene_tree.zig");
    _ = @import("input_actions.zig");
    _ = @import("scene_loader.zig");
}
