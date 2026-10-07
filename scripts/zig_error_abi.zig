    pub const ke_error_type = extern struct {
        name: ?[*:0]const u8,
        parent: ?*const ke_error_type,
    };

    pub const ke_error = extern struct {
        @"type": ?*const ke_error_type,
        message: ?[*:0]const u8,
        file: ?[*:0]const u8,
        line: u32,
        cause: ?*const ke_error,
    };

    pub extern fn ke_error_is(err: ?*const ke_error, @"type": *const ke_error_type) callconv(.c) bool;
