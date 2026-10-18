//! The names a scene file spells: node type names in the one form the script factory receives,
//! and the entity names one file declares for its parents and connections to refer to.

const std = @import("std");

const c = @import("c");
const heap = @import("heap");
const values = @import("scene_values.zig");

const E = @import("kerror").Errors(c);

pub const type_name_max = 128;

/// Returns the type name spelled the way the script factory receives it, or null when the result
/// would not fit the buffer; a longer name is refused, never truncated. Applying it to its own
/// result returns the same name.
pub fn normalizeTypeName(name: [*c]const u8, out: *[type_name_max]u8) ?[*:0]const u8 {
    if (name == null) return null;
    const src = std.mem.sliceTo(name, 0);
    var len: usize = 0;

    for (src, 0..) |ch, i| {
        if (ch == '+') {
            if (len + 1 >= out.len) return null;
            out[len] = '.';
            len += 1;
            continue;
        }
        if (std.ascii.isUpper(ch)) {
            const raw_prev: u8 = if (i > 0) src[i - 1] else '.';
            const prev: u8 = if (raw_prev == '+') '.' else raw_prev;
            const next_is_lower = i + 1 < src.len and std.ascii.isLower(src[i + 1]);
            const starts_word = prev != '.' and prev != '_' and !std.ascii.isDigit(prev) and
                (!std.ascii.isUpper(prev) or next_is_lower);
            if (starts_word) {
                if (len + 1 >= out.len) return null;
                out[len] = '_';
                len += 1;
            }
            if (len + 1 >= out.len) return null;
            out[len] = std.ascii.toLower(ch);
            len += 1;
            continue;
        }
        if (len + 1 >= out.len) return null;
        out[len] = ch;
        len += 1;
    }

    out[len] = 0;
    return @ptrCast(out);
}

/// Maps the names one scene file declares to their entities, so a later entity can name one as its
/// parent and a connection can name one as its target. The name copies live in the arena; the item
/// array is heap memory that `deinit` frees. A map belongs to one file's load.
pub const NameMap = struct {
    const Entry = struct { name: [*:0]u8, entity: c.ke_entity };

    items: ?[*]Entry = null,
    count: u32 = 0,
    capacity: u32 = 0,
    arena: *values.Arena,

    const initial_capacity: u32 = 16;

    /// What a name refers to: nothing, one entity, or more than one, which a reference cannot use.
    pub const Found = union(enum) { none, one: c.ke_entity, ambiguous };

    /// Records a name and its entity, growing the item array when it is full. A name may be
    /// recorded more than once; only a reference to it is refused. Fails as out of memory when the
    /// array cannot grow or the name cannot be copied.
    pub fn put(self: *NameMap, name: [*c]const u8, entity: c.ke_entity, out_error: [*c][*c]c.ke_error) bool {
        if (self.count == self.capacity) {
            const cap = if (self.capacity != 0) self.capacity * 2 else initial_capacity;
            const buf = heap.gpa.alloc(Entry, cap) catch {
                E.fail(out_error, .out_of_memory, "entity name table allocation failed", @src());
                return false;
            };
            if (self.items) |old| {
                @memcpy(buf[0..self.count], old[0..self.count]);
                heap.gpa.free(old[0..self.capacity]);
            }
            self.items = buf.ptr;
            self.capacity = cap;
        }
        const owned = self.arena.dupeZ(name) orelse {
            E.fail(out_error, .out_of_memory, "entity name copy failed", @src());
            return false;
        };
        self.items.?[self.count] = .{ .name = owned, .entity = entity };
        self.count += 1;
        return true;
    }

    pub fn find(self: *const NameMap, name: []const u8) Found {
        const items = self.items orelse return .none;
        var found: Found = .none;
        for (items[0..self.count]) |entry| {
            if (!std.mem.eql(u8, std.mem.span(entry.name), name)) continue;
            if (found != .none) return .ambiguous;
            found = .{ .one = entry.entity };
        }
        return found;
    }

    pub fn deinit(self: *NameMap) void {
        if (self.items) |items| heap.gpa.free(items[0..self.capacity]);
        self.items = null;
    }
};

const testing = std.testing;

fn normalizedName(name: [*c]const u8) []const u8 {
    const buf = struct {
        var storage: [type_name_max]u8 = undefined;
    };
    const out = normalizeTypeName(name, &buf.storage) orelse return "";
    return std.mem.sliceTo(out, 0);
}

test "a type name is spelled the same way whichever casing a scene authored" {
    try testing.expectEqualStrings("pong.ball", normalizedName("Pong.Ball"));
    try testing.expectEqualStrings("pong.ball", normalizedName("Pong+Ball"));
    try testing.expectEqualStrings("pong.ball", normalizedName("pong.ball"));
}

test "a run of capitals stays one word until a lowercase starts the next" {
    try testing.expectEqualStrings("http_server", normalizedName("HTTPServer"));
    try testing.expectEqualStrings("ui_label", normalizedName("UILabel"));
    try testing.expectEqualStrings("id", normalizedName("ID"));
}

test "a digit does not split the word it belongs to" {
    try testing.expectEqualStrings("sprite2d", normalizedName("Sprite2D"));
    try testing.expectEqualStrings("node3d", normalizedName("Node3D"));
    try testing.expectEqualStrings("collider2d", normalizedName("Collider2D"));
}

test "a character outside ascii keeps its case" {
    try testing.expectEqualStrings("État_ball", normalizedName("ÉtatBall"));
    try testing.expectEqualStrings("Ω_node", normalizedName("ΩNode"));
}

test "normalizing is idempotent, so a binding may apply it twice" {
    try testing.expectEqualStrings("paddle_controller", normalizedName("paddle_controller"));
    try testing.expectEqualStrings("pong.ball", normalizedName("pong.ball"));
    try testing.expectEqualStrings("sprite2d", normalizedName("sprite2d"));
}

test "a type name too long to normalize is refused rather than truncated" {
    var long: [type_name_max + 8]u8 = undefined;
    @memset(&long, 'A');
    long[long.len - 1] = 0;

    var buf: [type_name_max]u8 = undefined;
    try testing.expect(normalizeTypeName(@ptrCast(&long), &buf) == null);
}
