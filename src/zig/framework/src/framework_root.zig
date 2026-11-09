//! The root module of the framework library: it sets the standard options and pulls every file of
//! the plugin into the compilation so that their exports end up in the library.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_framework").logFn };

pub const _DllMainCRTStartup = @import("dll_entry")._DllMainCRTStartup;

comptime {
    _ = @import("mesh_shape.zig");
    _ = @import("asset_resolver.zig");
    _ = @import("scene_tree.zig");
    _ = @import("scene_hierarchy.zig");
    _ = @import("node_types.zig");
    _ = @import("input_actions.zig");
    _ = @import("scene_files.zig");
    _ = @import("scene_values.zig");
    _ = @import("scene_names.zig");
}
