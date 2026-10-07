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
        ApiStruct Vtable(string name, params ApiSlot[] slots) => new(name, null, [], [], slots.ToList());

        ApiStruct Handle(string vtable) => new($"{vtable}_handle", null, [], [], [
            new ApiSlot("destroy", "void", [], null, null, []) { Receiver = $"{vtable} *" }]);

        ApiSlot Slot(string name, string returns, params ApiParam[] ps) =>
            new(name, returns, [], null, null, ps.ToList());

        ApiParam P(string name, string type, params string[] tags) => new(name, type, tags, null);

        void Expect(string what, Action<ApiModel> build, string[] contains, string[] absent,
            IReadOnlyDictionary<string, ForeignType>? foreign = null, string[]? providers = null)

        {
            Register(what, failures =>
            {
                var model = new ApiModel();
            build(model);
            var classified = Classifier.Classify(model, (providers ?? []).ToHashSet(), [], ProbeConvention.Value);
            var emitted = ZigBackend.Render(model, classified, ProbeConvention.Value, foreign);
            if (Environment.GetEnvironmentVariable("KE_ZIG_SHAPES_DUMP") == what) Console.WriteLine(emitted);

            foreach (var needle in contains)
                if (!emitted.Contains(needle, StringComparison.Ordinal))
                    failures.Add($"{what}: expected to find \"{needle}\"");

            foreach (var needle in absent)
                if (emitted.Contains(needle, StringComparison.Ordinal))
                    failures.Add($"{what}: expected NOT to find \"{needle}\"");
            });
        }

        Expect("a fixed-size array field declares its extent and its element type",
            m => m.Structs.Add(new ApiStruct("ke_probe", null, [], [
                new ApiField("path", "char[256]", [], null),
                new ApiField("m", "float[16]", [], null),
                new ApiField("columns", "void *[8]", [], null),
            ], [])),
            contains: ["path: [256]u8,", "m: [16]f32,", "columns: [8]?*anyopaque,"],
            absent: ["char[256]", "float[16]"]);

        Expect("an enum member aliasing a sibling is a declaration, not a second case",
            m => m.Enums.Add(new ApiEnum("ke_probe_button", null, [
                new ApiEnumValue("KE_PROBE_BUTTON_1", "0", true, null),
                new ApiEnumValue("KE_PROBE_BUTTON_LEFT", "KE_PROBE_BUTTON_1", false, null),
            ])),
            contains: ["button_1 = 0,", "pub const left: @This() = .button_1;"],
            absent: ["left = KE_PROBE_BUTTON_1"]);

        Expect("a composed foreign type is reached through an import, not named bare",
            m =>
            {
                m.Structs.Add(new ApiStruct("ke_far_ctx", null, [], [], []) { External = true });
                m.Enums.Add(new ApiEnum("ke_far_kind", null, []) { External = true });
                m.Structs.Add(new ApiStruct("ke_probe", null, [], [
                    new ApiField("ctx", "ke_far_ctx *", [], null),
                    new ApiField("kind", "ke_far_kind", [], null),
                ], []));
            },
            contains: ["const far = @import(\"far.zig\");", "ctx: *far.abi.ke_far_ctx,", "kind: far.FarKind,"],
            absent: ["*ke_far_ctx,", "kind: ke_far_kind,"],
            foreign: new Dictionary<string, ForeignType>
            {
                ["ke_far_ctx"] = new("far", "far.zig", true),
                ["ke_far_kind"] = new("far", "far.zig", false),
            });

        Expect("a domain naming nothing foreign imports nothing",
            m => m.Structs.Add(new ApiStruct("ke_probe", null, [], [new ApiField("n", "uint32_t", [], null)], [])),
            contains: [],
            absent: ["@import("],
            foreign: new Dictionary<string, ForeignType> { ["ke_far_ctx"] = new("far", "far.zig", true) });

        Expect("a caller-allocated buffer is one writable span, not a written-back value",
            m =>
            {
                m.Structs.Add(new ApiStruct("ke_probe_event", null, [], [new ApiField("code", "uint32_t", [], null)], []));
                m.Structs.Add(Vtable("ke_probe",
                    Slot("drain", "uint32_t",
                        P("out_buf", "ke_probe_event *", "out", "array_of:capacity"),
                        P("capacity", "uint32_t"))));
                m.Structs.Add(Handle("ke_probe"));
            },
            contains: ["pub fn drain(self: Probe, out_buf: []abi.ke_probe_event) u32 {",
                       "self.ref.drain(self.ref, out_buf.ptr, @intCast(out_buf.len));"],
            absent: ["buf_out"],
            providers: ["ke_probe"]);

        Expect("a sequence of borrowed structs is a slice of the ABI's own struct",
            m =>
            {
                m.Structs.Add(new ApiStruct("ke_probe_term", null, ["value"],
                    [new ApiField("cid", "uint32_t", [], null)], []));
                m.Structs.Add(new ApiStruct("ke_probe_decl", null, ["borrowed"],
                [
                    new ApiField("terms", "const ke_probe_term *", ["array_of:term_count"], null),
                    new ApiField("term_count", "uint32_t", [], null),
                ], []));
                m.Structs.Add(Vtable("ke_probe",
                    Slot("declare", "uint64_t",
                        P("decls", "const ke_probe_decl *", "array_of:decl_count"),
                        P("decl_count", "uint32_t"))));
                m.Structs.Add(Handle("ke_probe"));
            },
            contains: ["pub fn declare(self: Probe, decls: []const abi.ke_probe_decl) u64 {",
                       "self.ref.declare(self.ref, decls.ptr, @intCast(decls.len));",
                       "terms: [*]const ke_probe_term,"],
            absent: ["decl_count: u32) u64 {", "decls: [*]const abi"],
            providers: ["ke_probe"]);

        Expect("a parameter shadowing a method of the same projection is renamed",
            m =>
            {
                m.Structs.Add(Vtable("ke_probe",
                    Slot("parent", "uint64_t", P("entity", "uint64_t")),
                    Slot("attach", "void", P("parent", "uint64_t"))));
                m.Structs.Add(Handle("ke_probe"));
            },
            contains: ["pub fn attach(self: Probe, parent_arg: u64) void {",
                       "self.ref.attach(self.ref, parent_arg);"],
            absent: ["pub fn attach(self: Probe, parent: u64)"],
            providers: ["ke_probe"]);

        Expect("a supplied handler is a trampoline over the caller's own state",
            m =>
            {
                m.Callbacks.Add(new ApiCallback("ke_probe_apply_fn", "_Bool", null, [
                    P("ctx", "void *", "context"),
                    P("name", "const char *", "utf8"),
                    P("out_error", "ke_error **"),
                ]));
                m.Structs.Add(Vtable("ke_probe",
                    Slot("register_apply", "_Bool",
                        P("apply", "ke_probe_apply_fn", "closure:ctx", "retained"),
                        P("ctx", "void *"),
                        P("out_error", "ke_error **"))));
                m.Structs.Add(Handle("ke_probe"));
            },
            contains: [
                "pub fn registerApply(self: Probe, ctx: anytype, comptime apply: "
                    + "fn (@TypeOf(ctx), [:0]const u8) Error!void) Error!void {",
                "const ApplyTrampoline = struct {",
                "fn call(ctx_lane: ?*anyopaque, name: [*:0]const u8, _: ?*?*abi.ke_error) callconv(.c) bool {",
                "apply(@ptrCast(@alignCast(ctx_lane.?)), std.mem.span(name)) catch return false;",
                "return true;",
                "self.ref.register_apply(self.ref, ApplyTrampoline.call, @ptrCast(ctx), &err)",
                "const std = @import(\"std\");",
            ],
            absent: ["@TypeOf(ctx), ?*anyopaque", "out_error: ?*?*abi.ke_error"],
            providers: ["ke_probe"]);

        Expect("a type nothing describes is declared opaque so its pointer is legal",
            m =>
            {
                m.Structs.Add(Vtable("ke_probe",
                    Slot("spawn", "ke_task *", P("out_error", "ke_error **")),
                    Slot("cancel", "void", P("task", "ke_task *"))));
                m.Structs.Add(Handle("ke_probe"));
            },
            contains: ["pub const ke_task = opaque {};",
                       "pub fn spawn(self: Probe) Error!*abi.ke_task {",
                       "pub fn cancel(self: Probe, task: *abi.ke_task) void {"],
            absent: ["pub const ke_error = opaque", "pub const ke_error_type = opaque"],
            providers: ["ke_probe"]);

        Expect("an undescribed type reached by value is not made opaque",
            m => m.Structs.Add(new ApiStruct("ke_probe", null, [], [
                new ApiField("held", "ke_probe_kind", [], null),
                new ApiField("addressed", "ke_probe_body *", [], null),
            ], [])),
            contains: ["held: ke_probe_kind,",
                       "pub const ke_probe_body = opaque {};",
                       "addressed: *ke_probe_body,"],
            absent: ["pub const ke_probe_kind = opaque {};"]);

        Expect("a failure crosses as an error union one way and an optional error the other",
            m =>
            {
                m.Callbacks.Add(new ApiCallback("ke_probe_body_fn", "void", null, [
                    P("data", "void *", "context"),
                    P("out_failure", "const ke_error_type **"),
                ]));
                m.Callbacks.Add(new ApiCallback("ke_probe_done_fn", "void", null, [
                    P("data", "void *", "context"),
                    P("failure", "const ke_error_type *"),
                ]));
                m.Structs.Add(Vtable("ke_probe",
                    Slot("run", "void",
                        P("body", "ke_probe_body_fn", "closure:data"),
                        P("data", "void *"),
                        P("done", "ke_probe_done_fn", "closure:tail"),
                        P("tail", "void *"))));
                m.Structs.Add(Handle("ke_probe"));
            },
            contains: [
                "pub fn run(self: Probe, data: anytype, comptime body: fn (@TypeOf(data)) Error!void, "
                    + "tail: anytype, comptime done: fn (@TypeOf(tail), ?Error) void) void {",
                "fn call(data_lane: ?*anyopaque, out_failure: ?*?*const abi.ke_error_type) callconv(.c) void {",
                "body(@ptrCast(@alignCast(data_lane.?))) catch |e| {",
                "if (out_failure) |slot| slot.* = errorType(e);",
                "fn call(data_lane: ?*anyopaque, failure: ?*const abi.ke_error_type) callconv(.c) void {",
                "done(@ptrCast(@alignCast(data_lane.?)), errorFrom(failure));",
                "fn errorType(e: Error) *const abi.ke_error_type {",
                "fn errorFrom(t: ?*const abi.ke_error_type) ?Error {",
            ],
            absent: ["?Error) Error!void", "failure: *const abi.ke_error_type"],
            providers: ["ke_probe"]);

        Expect("a vtable the caller implements is filled from a type the compiler looks methods up on",
            m =>
            {
                m.Structs.Add(new ApiStruct("ke_probe_sink", null, [], [
                    new ApiField("handle", "void *", [], null),
                    new ApiField("min_level", "int32_t", [], null),
                ], [
                    new ApiSlot("write", "void", [], null, null, [P("text", "const char *", "utf8")])
                        { Receiver = "ke_probe_sink *" },
                    new ApiSlot("destroy", "void", [], null, null, []) { Receiver = "ke_probe_sink *" },
                ]));
                m.Structs.Add(Vtable("ke_probe",
                    Slot("add_sink", "bool",
                        P("sink", "ke_probe_sink", "callback"),
                        P("out_error", "ke_error **"))));
                m.Structs.Add(Handle("ke_probe"));
            },
            contains: [
                "pub fn addSink(self: Probe, sink: anytype, min_level: i32) Error!void {",
                "const Target = @TypeOf(sink);",
                "fn write(self_lane: *abi.ke_probe_sink, text: [*:0]const u8) callconv(.c) void {",
                "return @as(Target, @ptrCast(@alignCast(self_lane.handle.?))).write(std.mem.span(text));",
                "const sink_native = abi.ke_probe_sink{",
                "    .handle = @ptrCast(sink),",
                "    .min_level = min_level,",
                "    .write = SinkVtable.write,",
                "    .destroy = SinkVtable.destroy,",
                "if (!self.ref.add_sink(self.ref, sink_native, &err)) return raise(err);",
            ],
            absent: ["sink: abi.ke_probe_sink", "ProbeSink = struct"],
            providers: ["ke_probe"]);

        Expect("an engine object crosses as a projection with no lifetime of its own",
            m =>
            {
                m.Structs.Add(Vtable("ke_probe_ctx", Slot("spawn", "u64")));
                m.Structs.Add(Vtable("ke_probe",
                    Slot("attach", "bool", P("ctx", "ke_probe_ctx *", "ctx"), P("out_error", "ke_error **"))));
                m.Structs.Add(Handle("ke_probe"));
            },
            contains: [
                "pub const ProbeCtx = struct {",
                "pub fn borrow(ref: *abi.ke_probe_ctx) ProbeCtx {",
                "        return .{ .ref = ref };",
                "pub fn attach(self: Probe, ctx: ProbeCtx) Error!void {",
                "if (!self.ref.attach(self.ref, ctx.ref, &err)) return raise(err);",
            ],
            absent: [
                "ctx: *abi.ke_probe_ctx)",
                "pub fn init(handle: abi.ke_probe_ctx_handle)",
                "pub fn deinit(self: *ProbeCtx)",
            ],
            providers: ["ke_probe"]);

        Expect("a parameter bag becomes a struct of defaults, with the handler and its state outside",
            m =>
            {
                m.Callbacks.Add(new ApiCallback("ke_probe_run_fn", "void", null, [
                    P("data", "void *", "context"),
                ]));
                m.Structs.Add(new ApiStruct("ke_probe_params", null, [], [
                    new ApiField("name", "const char *", ["utf8"], null),
                    new ApiField("data", "void *", ["context"], null),
                    new ApiField("run", "ke_probe_run_fn", ["closure:data"], null),
                    new ApiField("terms", "const uint32_t *", ["array_of:term_count", "default:empty"], null),
                    new ApiField("term_count", "uint32_t", [], null),
                    new ApiField("pinned", "uint32_t", ["default:0"], null),
                ], []));
                m.Structs.Add(Vtable("ke_probe",
                    Slot("register", "bool",
                        P("p", "const ke_probe_params *", "expand"),
                        P("out_error", "ke_error **"))));
                m.Structs.Add(Handle("ke_probe"));
            },
            contains: [
                "pub const ProbeParams = struct {",
                "    name: [:0]const u8,",
                "    terms: []const u32 = &.{},\n    pinned: u32 = 0,\n};",
                "pub fn register(self: Probe, data: anytype, comptime run: fn (@TypeOf(data)) void, "
                    + "p: ProbeParams) Error!void {",
                "    .name = p.name.ptr,",
                "    .data = @ptrCast(data),",
                "    .run = RunTrampoline.call,",
                "    .terms = p.terms.ptr,",
                "    .term_count = @intCast(p.terms.len),",
                "if (!self.ref.register(self.ref, &p_native, &err)) return raise(err);",
            ],
            absent: ["p: *const abi.ke_probe_params", "name: [*:0]const u8,\n    data:"],
            providers: ["ke_probe"]);
    }
}
