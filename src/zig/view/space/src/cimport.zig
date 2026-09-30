pub const c = @cImport({
    @cInclude("kernel_engine/common/error.h");
    @cInclude("kernel_engine/common/math.h");
    @cInclude("kernel_engine/view/view_space.h");
    @cInclude("kernel_engine/view/space/view_space_rh_create.h");
    @cInclude("kernel_engine/view/space/view_space_lh_create.h");
});
