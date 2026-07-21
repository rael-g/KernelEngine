// The window-backend seam: what a platform device must provide for the core to
// drive it. Kept as an explicit vtable rather than folded into the GLFW code so
// a second backend (SDL, a headless test device) is a new file filling this
// struct, not a rewrite of the core.

pub const Config = struct {
    title: [*:0]const u8,
    width: u32,
    height: u32,
    fullscreen: bool,
    vsync: bool,
};

pub const EventType = enum(u8) {
    close,
    resize,
    focus_gained,
    focus_lost,
    key_down,
    key_up,
    mouse_move,
    mouse_button_down,
    mouse_button_up,
    mouse_scroll,
};

pub const Event = struct {
    type: EventType,
    data: union {
        none: void,
        resize: struct { width: u32, height: u32 },
        key: struct { key_code: u32, alt: bool, ctrl: bool, shift: bool },
        mouse_move: struct { x: f32, y: f32 },
        mouse_button: struct { button: u8, x: f32, y: f32 },
        mouse_scroll: struct { delta_x: f32, delta_y: f32 },
    } = .{ .none = {} },
};

/// Called once per event drained by pollEvents.
pub const EventSink = struct {
    ctx: *anyopaque,
    on_event: *const fn (ctx: *anyopaque, ev: Event) void,
};

pub const VTable = struct {
    initialize: *const fn (self: *anyopaque, config: Config) bool,
    shutdown: *const fn (self: *anyopaque) void,
    poll_events: *const fn (self: *anyopaque, sink: EventSink) void,
    should_close: *const fn (self: *anyopaque) bool,
    set_title: *const fn (self: *anyopaque, title: [*:0]const u8) void,
    get_size: *const fn (self: *anyopaque, width: *u32, height: *u32) void,
    get_native_handle: *const fn (self: *anyopaque) ?*anyopaque,
    /// Releases whatever the device itself allocated; called after shutdown.
    destroy: *const fn (self: *anyopaque) void,
};

pub const Device = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub fn initialize(d: Device, config: Config) bool {
        return d.vtable.initialize(d.ptr, config);
    }
    pub fn shutdown(d: Device) void {
        d.vtable.shutdown(d.ptr);
    }
    pub fn pollEvents(d: Device, sink: EventSink) void {
        d.vtable.poll_events(d.ptr, sink);
    }
    pub fn shouldClose(d: Device) bool {
        return d.vtable.should_close(d.ptr);
    }
    pub fn setTitle(d: Device, title: [*:0]const u8) void {
        d.vtable.set_title(d.ptr, title);
    }
    pub fn getSize(d: Device, width: *u32, height: *u32) void {
        d.vtable.get_size(d.ptr, width, height);
    }
    pub fn getNativeHandle(d: Device) ?*anyopaque {
        return d.vtable.get_native_handle(d.ptr);
    }
    pub fn destroy(d: Device) void {
        d.vtable.destroy(d.ptr);
    }
};
