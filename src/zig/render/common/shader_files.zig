//! Reads what the build wrote beside a compiled shader: the compiled code a device loads and the
//! reflection a binder builds layouts from.

const libc = @cImport({
    @cInclude("stdio.h");
});

/// The file functions for the C namespace `c`, which must include `kernel_engine/common/error.h`.
pub fn ShaderFiles(comptime c: type) type {
    return struct {
        /// The whole contents of the file at `path`, owned by the caller and freed with `gpa`. Null
        /// with the error filled: not found when the file does not open, I/O when it cannot be
        /// sized or fully read, out of memory when the buffer cannot be allocated.
        pub fn read(gpa: @import("std").mem.Allocator, path: [:0]const u8, out_error: [*c][*c]c.ke_error) ?[]u8 {
            const fp = libc.fopen(path.ptr, "rb") orelse {
                c.ke_error_set(out_error, &c.KE_ERROR_NOT_FOUND, "read shader file: shader file not found", @src().file, @intCast(@src().line), null);
                return null;
            };
            defer _ = libc.fclose(fp);
            _ = libc.fseek(fp, 0, libc.SEEK_END);
            const size_signed = libc.ftell(fp);
            _ = libc.fseek(fp, 0, libc.SEEK_SET);
            if (size_signed < 0) {
                c.ke_error_set(out_error, &c.KE_ERROR_IO, "read shader file: failed to size shader file", @src().file, @intCast(@src().line), null);
                return null;
            }
            const size: usize = @intCast(size_signed);
            const bytes = gpa.alloc(u8, size) catch {
                c.ke_error_set(out_error, &c.KE_ERROR_OUT_OF_MEMORY, "read shader file: shader buffer allocation failed", @src().file, @intCast(@src().line), null);
                return null;
            };
            if (libc.fread(bytes.ptr, 1, size, fp) != size) {
                c.ke_error_set(out_error, &c.KE_ERROR_IO, "read shader file: failed to read shader file", @src().file, @intCast(@src().line), null);
                gpa.free(bytes);
                return null;
            }
            return bytes;
        }
    };
}
