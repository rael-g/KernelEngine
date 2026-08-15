
pub const c = @cImport({
    @cInclude("kernel_engine/common/error.h");
    @cInclude("kernel_engine/scheduler/scheduler.h");
    @cInclude("kernel_engine/scheduler/enki/enki_scheduler.h");
    @cInclude("TaskScheduler_c.h");
});
