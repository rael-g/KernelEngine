//! The names of the generic error types in one place. `generic` holds them as NUL-terminated
//! strings in an order that other files index by position, and each named constant reads one entry
//! of it.

/// The position of each name is the position of its kind in the enum of kinds declared in the file
/// kerror.zig, which indexes this array with `@intFromEnum`. Moving an entry changes which kind it
/// names, so the two lists must stay in the same order.
pub const generic = [_][*:0]const u8{
    "ke.error",
    "ke.error.not_found",
    "ke.error.io",
    "ke.error.out_of_memory",
    "ke.error.invalid_argument",
    "ke.error.not_initialized",
    "ke.error.not_supported",
    "ke.error.already_exists",
};

pub const general = generic[0];
pub const not_found = generic[1];
pub const io = generic[2];
pub const out_of_memory = generic[3];
pub const invalid_argument = generic[4];
pub const not_initialized = generic[5];
pub const not_supported = generic[6];
pub const already_exists = generic[7];
