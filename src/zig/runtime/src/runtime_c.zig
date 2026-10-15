//! The C declarations of the runtime plugin, imported once so every file shares their types.

pub const c = @cImport({
    @cInclude("kernel_engine/runtime/runtime_create.h");
    @cInclude("kernel_engine/runtime/system_ctx.h");
});
