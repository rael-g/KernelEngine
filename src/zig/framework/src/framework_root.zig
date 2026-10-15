//! The root module of the framework library: it sets the standard options and pulls every file of
//! the plugin into the compilation so that their exports end up in the library.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };

pub const _DllMainCRTStartup = @import("kerror")._DllMainCRTStartup;

comptime {
    _ = @import("components_apply.zig");
    _ = @import("mesh_shape.zig");
    _ = @import("asset_resolver.zig");
    _ = @import("world.zig");
    _ = @import("scene_tree.zig");
    _ = @import("scene_hierarchy.zig");
    _ = @import("input_actions.zig");
    _ = @import("scene_loader.zig");
    _ = @import("scene_values.zig");
    _ = @import("scene_names.zig");
    _ = @import("signal_bus.zig");
    _ = @import("script_host.zig");
}
