//! Imports, as one C namespace, the contract headers the grouped resource binder reads and its
//! factory header.

pub const c = @cImport({
    @cInclude("kernel_engine/common/error.h");
    @cInclude("kernel_engine/render/gpu/gpu_device.h");
    @cInclude("kernel_engine/render/gpu/gpu_commands.h");
    @cInclude("kernel_engine/render/gpu/gpu_render_target.h");
    @cInclude("kernel_engine/render/binding/resource_binder.h");
    @cInclude("kernel_engine/render/binder_grouped/resource_binder_grouped_create.h");
});
