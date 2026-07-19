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

comptime {
    _ = @import("components_apply.zig");
    _ = @import("mesh_shape.zig");
}
