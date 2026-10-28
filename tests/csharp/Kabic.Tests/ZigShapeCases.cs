using Kabic;
using Kabic.Zig;

namespace Kabic.Tests;

internal static class ZigShapeCases
{
    static readonly Dictionary<string, Action<List<string>>> Registered = new();
    static int declared;

    public static IReadOnlyDictionary<string, Action<List<string>>> All()
    {
        if (declared++ == 0) Declare();
        return Registered;
    }

    static void Register(string what, Action<List<string>> run)
    {
        var name = what;
        for (var n = 2; Registered.ContainsKey(name); n++) name = $"{what} ({n})";
        Registered[name] = run;
    }

    static void Declare()
    {
        ApiSlot Slot(string name, string returns, string receiver, params ApiParam[] ps) =>
            new(name, returns, [], null, null, ps.ToList()) { Receiver = receiver };

        ApiParam P(string name, string type, params string[] tags) => new(name, type, tags, null);

        ApiField F(string name, string type, params string[] tags) => new(name, type, tags, null);

        void Expect(string what, Action<ApiModel> build, string[] contains, string[]? absent = null,
            IReadOnlyDictionary<string, string>? foreign = null)
        {
            Register(what, failures =>
            {
                var model = new ApiModel();
                build(model);
                var emitted = ZigWriter.Render(model, foreign ?? new Dictionary<string, string>());
                if (Environment.GetEnvironmentVariable("KE_ZIG_SHAPES_DUMP") == what) Console.WriteLine(emitted);

                foreach (var needle in contains)
                    if (!emitted.Contains(needle, StringComparison.Ordinal))
                        failures.Add($"{what}: expected to find \"{needle}\"");

                foreach (var needle in absent ?? [])
                    if (emitted.Contains(needle, StringComparison.Ordinal))
                        failures.Add($"{what}: expected NOT to find \"{needle}\"");
            });
        }

        void Refuse(string what, Action<ApiModel> build, string message)
        {
            Register(what, failures =>
            {
                var model = new ApiModel();
                build(model);
                try
                {
                    ZigWriter.Render(model, new Dictionary<string, string>());
                    failures.Add($"{what}: expected the declaration to be refused");
                }
                catch (NotSupportedException e) when (e.Message.Contains(message, StringComparison.Ordinal)) { }
                catch (NotSupportedException e) { failures.Add($"{what}: refused with \"{e.Message}\""); }
            });
        }

        Expect("a fixed-size array field declares its extent and its element type",
            m => m.Structs.Add(new ApiStruct("ke_probe", null, [], [
                F("path", "char[256]"),
                F("m", "float[16]"),
                F("columns", "void *[8]"),
            ], [])),
            contains: ["path: [256]u8 = std.mem.zeroes([256]u8),", "m: [16]f32 = std.mem.zeroes([16]f32),", "columns: [8]?*anyopaque = std.mem.zeroes([8]?*anyopaque),"],
            absent: ["char[256]", "float[16]"]);

        Expect("an enum is its C integer type and a constant per value, an alias included",
            m => m.Enums.Add(new ApiEnum("ke_probe_button", null, [
                new ApiEnumValue("KE_PROBE_BUTTON_1", "0", true, null),
                new ApiEnumValue("KE_PROBE_BUTTON_LEFT", "KE_PROBE_BUTTON_1", false, null),
            ])),
            contains: ["pub const ke_probe_button = c_uint;",
                       "pub const KE_PROBE_BUTTON_1: ke_probe_button = 0;",
                       "pub const KE_PROBE_BUTTON_LEFT: ke_probe_button = KE_PROBE_BUTTON_1;"],
            absent: ["enum(u32)"]);

        Expect("an enum with a negative value is a signed integer",
            m => m.Enums.Add(new ApiEnum("ke_probe_side", null, [
                new ApiEnumValue("KE_PROBE_SIDE_BACK", "-1", true, null),
            ])),
            contains: ["pub const ke_probe_side = c_int;"],
            absent: ["c_uint"]);

        Expect("a type another domain declares is reached through its module",
            m => m.Structs.Add(new ApiStruct("ke_probe", null, [], [
                F("ecs", "ke_far_ecs *"),
                F("kind", "ke_far_kind"),
            ], [])),
            contains: ["const far = @import(\"far\");", "ecs: ?*far.ke_far_ecs = std.mem.zeroes(?*far.ke_far_ecs),", "kind: far.ke_far_kind = std.mem.zeroes(far.ke_far_kind),"],
            absent: ["?*ke_far_ecs,"],
            foreign: new Dictionary<string, string> { ["ke_far_ecs"] = "far", ["ke_far_kind"] = "far" });

        Expect("a domain naming nothing foreign imports nothing",
            m => m.Structs.Add(new ApiStruct("ke_probe", null, [], [F("n", "uint32_t")], [])),
            contains: ["n: u32 = std.mem.zeroes(u32),"],
            absent: ["@import(\"far\")"],
            foreign: new Dictionary<string, string> { ["ke_far_ecs"] = "far" });

        Expect("every pointer is nullable, and a counted one reaches many",
            m => m.Structs.Add(new ApiStruct("ke_probe", null, [], [
                F("one", "ke_probe *"),
                F("many", "const uint32_t *", "array_of:count"),
                F("count", "uint32_t"),
                F("name", "const char *"),
                F("names", "const char *const *", "array_of:count"),
                F("bytes", "const char *", "array_of:count"),
                F("user", "void *"),
                F("seen", "const void *"),
            ], [])),
            contains: ["one: ?*ke_probe = std.mem.zeroes(?*ke_probe),", "many: ?[*]const u32 = std.mem.zeroes(?[*]const u32),", "name: ?[*:0]const u8 = std.mem.zeroes(?[*:0]const u8),",
                       "names: ?[*]const ?[*:0]const u8 = std.mem.zeroes(?[*]const ?[*:0]const u8),", "bytes: ?[*]const u8 = std.mem.zeroes(?[*]const u8),", "user: ?*anyopaque = std.mem.zeroes(?*anyopaque),",
                       "seen: ?*const anyopaque = std.mem.zeroes(?*const anyopaque),"]);

        Expect("a slot is a nullable C function pointer that takes its receiver first",
            m => m.Structs.Add(new ApiStruct("ke_probe", null, [], [F("handle", "void *")], [
                Slot("count", "uint32_t", "struct ke_probe *"),
                Slot("fill", "ke_result", "struct ke_probe *", P("out_items", "ke_item *", "out", "array_of:capacity"),
                    P("capacity", "uint32_t")),
            ])),
            contains: ["handle: ?*anyopaque = std.mem.zeroes(?*anyopaque),",
                       "count: ?*const fn (?*ke_probe) callconv(.c) u32 = null,",
                       "fill: ?*const fn (?*ke_probe, ?[*]far.ke_item, u32) callconv(.c) result.ke_result = null,"],
            absent: ["self:"],
            foreign: new Dictionary<string, string> { ["ke_item"] = "far", ["ke_result"] = "result" });

        Expect("members keep declaration order when slots and fields interleave",
            m => m.Structs.Add(new ApiStruct("ke_probe", null, [], [F("handle", "void *")], [
                Slot("write", "void", "struct ke_probe *"),
            ])
            { Order = ["write", "handle"] }),
            contains: ["write: ?*const fn (?*ke_probe) callconv(.c) void = null,\n    handle: ?*anyopaque = std.mem.zeroes(?*anyopaque),"]);

        Expect("an anonymous union is an inline extern union",
            m => m.Structs.Add(new ApiStruct("ke_probe_variant", null, [], [
                F("type", "uint32_t"),
                new ApiField("unnamed_0", "", [], null)
                {
                    Inline = new ApiStruct("", null, [], [F("i", "int64_t"), F("f", "double")], []) { IsUnion = true },
                },
            ], [])),
            contains: ["@\"type\": u32 = std.mem.zeroes(u32),", "unnamed_0: extern union {\n        i: i64,\n        f: f64,\n    } = .{ .i = std.mem.zeroes(i64) },"]);

        Expect("a function-pointer typedef is a nullable C function pointer",
            m => m.Callbacks.Add(new ApiCallback("ke_probe_done_fn", "void", null, [
                P("user", "void *", "context"), P("outcome", "ke_result"),
            ])),
            contains: ["pub const ke_probe_done_fn = ?*const fn (?*anyopaque, result.ke_result) callconv(.c) void;"],
            absent: [],
            foreign: new Dictionary<string, string> { ["ke_result"] = "result" });

        Expect("an inline function-pointer parameter is spelled as one",
            m => m.Structs.Add(new ApiStruct("ke_probe", null, [], [], [
                Slot("compile", "void", "struct ke_probe *", P("on_ready", "void (*)(uint64_t, void *)")),
            ])),
            contains: ["compile: ?*const fn (?*ke_probe, ?*const fn (u64, ?*anyopaque) callconv(.c) void) callconv(.c) void = null,"]);

        Expect("a record declared and never defined is opaque",
            m =>
            {
                m.Opaques.Add("ke_task");
                m.Structs.Add(new ApiStruct("ke_probe", null, [], [F("task", "ke_task *")], []));
            },
            contains: ["pub const ke_task = opaque {};", "task: ?*ke_task = std.mem.zeroes(?*ke_task),"]);

        Expect("a field named after a Zig primitive is quoted",
            m => m.Structs.Add(new ApiStruct("ke_probe", null, [], [F("u8", "uint8_t"), F("error", "int32_t")], [])),
            contains: ["@\"u8\": u8 = std.mem.zeroes(u8),", "@\"error\": i32 = std.mem.zeroes(i32),"]);

        Expect("a macro constant keeps a declared type and leaves a C-typed integer a Zig literal",
            m =>
            {
                m.TypeAliases["ke_probe_id"] = "uint32_t";
                m.Structs.Add(new ApiStruct("ke_probe_handle", null, [], [F("bits", "uint32_t")], []));
                m.Constants.Add(new ApiConstant("KE_PROBE_ID_NONE", "ke_probe_id", "0", null, "The id nothing has."));
                m.Constants.Add(new ApiConstant("KE_PROBE_MAX", "unsigned long", "18446744073709551615", null, null));
                m.Constants.Add(new ApiConstant("KE_PROBE_NAME", "const char *", "\"probe\"", null, null));
                m.Constants.Add(new ApiConstant("KE_PROBE_NONE", "ke_probe_handle", null, [new ApiConstantField("bits", "0")], null));
            },
            contains: ["/// The id nothing has.\npub const KE_PROBE_ID_NONE: ke_probe_id = 0;",
                       "pub const KE_PROBE_MAX = 18446744073709551615;",
                       "pub const KE_PROBE_NAME = \"probe\";",
                       "pub const KE_PROBE_NONE: ke_probe_handle = .{ .bits = 0 };"],
            absent: ["c_ulong"]);

        Register("a factory header declares each function the plugin exports as external", failures =>
        {
            var model = new ApiModel();
            model.Structs.Add(new ApiStruct("ke_probe_params", null, [], [F("gravity", "float")], []));
            model.Functions.Add(new ApiFunction("ke_probe_create", "ke_result", "Creates a probe.", null, [
                P("params", "const ke_probe_params *"), P("out_probe", "ke_probe_handle *", "out"),
            ]));
            var emitted = ZigWriter.Render(model, new Dictionary<string, string> { ["ke_result"] = "result", ["ke_probe_handle"] = "probe" }, factory: true);
            const string expected = "/// Creates a probe.\npub extern fn ke_probe_create(params: ?*const ke_probe_params, out_probe: ?*probe.ke_probe_handle) result.ke_result;";
            if (!emitted.Contains(expected, StringComparison.Ordinal))
                failures.Add($"a factory header: expected to find \"{expected}\"");
        });

        Expect("an opaque record another root defines is reached through its module",
            m =>
            {
                m.Opaques.Add("ke_far");
                m.Structs.Add(new ApiStruct("ke_probe", null, [], [F("far", "struct ke_far *")], []));
            },
            contains: ["far: ?*far.ke_far = std.mem.zeroes(?*far.ke_far),"],
            absent: ["pub const ke_far = opaque {};"],
            foreign: new Dictionary<string, string> { ["ke_far"] = "far" });

        Refuse("a type nothing describes is refused by value",
            m => m.Structs.Add(new ApiStruct("ke_probe", null, [], [F("held", "ke_probe_kind")], [])),
            "ke_probe.held: ke_probe_kind is held by value and no domain describes it");

        Refuse("a contract declaring a plain function is refused",
            m => m.Functions.Add(new ApiFunction("ke_probe_create", "void", null, null, [])),
            "declares vtable shapes only");
    }
}
