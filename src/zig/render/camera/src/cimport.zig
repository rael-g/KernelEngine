//! The one C import of this plugin, exported as `c`: the headers of the camera.

pub const c = @cImport({
    @cInclude("kernel_engine/common/error.h");
    @cInclude("kernel_engine/math/math.h");
    @cInclude("kernel_engine/render/components.h");
    @cInclude("kernel_engine/render/camera.h");
    @cInclude("kernel_engine/view/view_space.h");
    @cInclude("kernel_engine/render/camera/camera_create.h");
});
