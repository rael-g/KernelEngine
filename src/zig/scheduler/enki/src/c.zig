// Single @cImport for the plugin — separate blocks would produce distinct Zig
// types for the same C struct, so anything crossing between these files would
// stop typechecking.

pub const c = @cImport({
    @cInclude("kernel_engine/common/error.h");
    @cInclude("kernel_engine/scheduler/scheduler.h");
    @cInclude("kernel_engine/scheduler/enki/enki_scheduler.h");
    // enkiTS ships a C API alongside its C++ one; this plugin uses the C API so
    // the whole module stays Zig with no C++ toolchain involved.
    @cInclude("TaskScheduler_c.h");
});
