//! Imports every C header the plugin uses in one translation unit, exported as `c`.

pub const c = @cImport({
    @cInclude("kernel_engine/common/error.h");
    @cInclude("kernel_engine/logger/logger.h");
    @cInclude("kernel_engine/physics/physics_2d.h");
    @cInclude("kernel_engine/physics/box2d/box2d_physics.h");
    @cInclude("box2d/box2d.h");
});
