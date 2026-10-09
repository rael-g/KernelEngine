//! The root module of the framework library. It sets the standard options, re-exports the DLL
//! start-up symbol of the error module, and imports every file of the plugin in a comptime block,
//! so that each file's exports are compiled into the library.
//!
//! The files carry the contracts of the plugin. world.zig makes the world and its registry of
//! component field tables and appliers, and components_apply.zig and component_fields_apply.zig
//! are the two ways those write authored values into a component. scene_tree.zig is the tree of
//! nodes over the ecs, and scene_hierarchy.zig keeps their world matrices current with the help
//! of mat4.zig. scene_loader.zig turns scene files into nodes, components and connections, with
//! asset_resolver.zig resolving textures, meshes, materials and fonts, and mesh_shape.zig baking
//! the primitive meshes. signal_bus.zig carries signals between entities, input_actions.zig names
//! the input held in a frame, script_host.zig binds script instances to entities, and c.zig is
//! the shared C import.

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
    _ = @import("signal_bus.zig");
    _ = @import("script_host.zig");
}
