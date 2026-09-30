#!/usr/bin/env dotnet run
#:project ../src/csharp/kabic/Kabic.ZigBackend/Kabic.ZigBackend.csproj

using Kabic;
using Kabic.Zig;

var failures = new List<string>();
var checks = 0;

ApiStruct Vtable(string name, params ApiSlot[] slots) => new(name, null, [], [], slots.ToList());

ApiStruct Handle(string vtable) => new($"{vtable}_handle", null, [], [], [
    new ApiSlot("destroy", "void", [], null, null, []) { Receiver = $"{vtable} *" }]);

ApiSlot Slot(string name, string returns, params ApiParam[] ps) =>
    new(name, returns, [], null, null, ps.ToList());

ApiParam P(string name, string type, params string[] tags) => new(name, type, tags, null);

/// <summary>
/// Renders one domain the way the driver does, with the foreign map it derives, and
/// checks what the module says. A Zig module is checked by its text here and by
/// <c>zig ast-check</c> over the sweep; the text is what says <em>which</em> form was
/// rendered, which a parse cannot.
/// </summary>
void Expect(string what, Action<ApiModel> build, string[] contains, string[] absent,
    IReadOnlyDictionary<string, ForeignType>? foreign = null, string[]? providers = null)
{
    checks++;
    var model = new ApiModel();
    build(model);
    var classified = Classifier.Classify(model, (providers ?? []).ToHashSet(), [], Convention.KernelEngine);
    var emitted = ZigBackend.Render(model, classified, Convention.KernelEngine, foreign);
    if (Environment.GetEnvironmentVariable("KE_ZIG_SHAPES_DUMP") == what) Console.WriteLine(emitted);

    foreach (var needle in contains)
        if (!emitted.Contains(needle, StringComparison.Ordinal))
            failures.Add($"{what}: expected to find \"{needle}\"");

    foreach (var needle in absent)
        if (emitted.Contains(needle, StringComparison.Ordinal))
            failures.Add($"{what}: expected NOT to find \"{needle}\"");
}

// A fixed extent belongs in front of the element type in Zig, and the element goes on
// through the primitive table. Left as a C declarator suffix the whole spelling misses
// that table, and the module names a type nothing declares.
Expect("a fixed-size array field declares its extent and its element type",
    m => m.Structs.Add(new ApiStruct("ke_probe", null, [], [
        new ApiField("path", "char[256]", [], null),
        new ApiField("m", "float[16]", [], null),
        new ApiField("columns", "void *[8]", [], null),
    ], [])),
    contains: ["path: [256]u8,", "m: [16]f32,", "columns: [8]?*anyopaque,"],
    absent: ["char[256]", "float[16]"]);

// An enum member whose C initialiser names a sibling is a second name for a case that
// already exists, not a case of its own. Zig refuses two fields sharing a tag value, so
// the alias is a declaration -- and emitting the C initialiser verbatim would name a
// symbol the module never declares.
Expect("an enum member aliasing a sibling is a declaration, not a second case",
    m => m.Enums.Add(new ApiEnum("ke_probe_button", null, [
        new ApiEnumValue("KE_PROBE_BUTTON_1", "0", true, null),
        new ApiEnumValue("KE_PROBE_BUTTON_LEFT", "KE_PROBE_BUTTON_1", false, null),
    ])),
    contains: ["button_1 = 0,", "pub const left: @This() = .button_1;"],
    absent: ["left = KE_PROBE_BUTTON_1"]);

// A type this domain composes is emitted by the domain that owns it, so this module
// reaches it through an import. Zig has no ambient namespace for the bare name to
// resolve in; a struct is part of the layout and sits under the owner's abi block,
// an enum is a projection and sits at its top level.
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

// A domain naming nothing foreign imports nothing: an unused import is a compile error
// in Zig, so emitting the map wholesale would refuse every module that composes less
// than it is handed.
Expect("a domain naming nothing foreign imports nothing",
    m => m.Structs.Add(new ApiStruct("ke_probe", null, [], [new ApiField("n", "uint32_t", [], null)], [])),
    contains: [],
    absent: ["@import("],
    foreign: new Dictionary<string, ForeignType> { ["ke_far_ctx"] = new("far", "far.zig", true) });

// A buffer the caller allocates and the callee fills is written back and counted at
// once. It is the memory, so there is no local to declare and take the address of, and
// the capacity the ABI asks for separately comes off the span.
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

// Zig refuses a parameter that shadows an outer declaration. A vtable declaring both a
// `parent` slot and a `parent` parameter is not a mistake in the header -- in C the two
// live in different scopes, and only the projection puts them in the same one.
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

// A handler the caller supplies travels as the C pair it already is: a function pointer
// and the state it reaches its own data through. Zig closes over nothing at runtime, so
// the state stays the caller's memory and the projection retains nothing -- and the
// context lane, being how the state comes back, is not something the handler is asked
// for. Where the typedef declares a ke_error** lane the handler reports through Zig's
// own error union, which is what that lane is the C spelling of.
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

// A name no domain describes, reached only through a pointer, is a C type forward
// declared and never defined -- the header hands out its address and nothing else. Zig
// says that with opaque, and saying it is what makes the pointer legal: the bare name
// alone leaves the module naming a symbol nothing declares. The types the ABI preamble
// writes by hand are not among them, or the error channel itself would be invented.
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

// The same undescribed name by value is not a handle. A layout this domain cannot see
// is a defect in the description, so the module goes on naming the symbol nothing
// declares and stops compiling -- which is the signal. Inventing an opaque here would
// trade a refusal to build for a field the caller can never reach.
Expect("an undescribed type reached by value is not made opaque",
    m => m.Structs.Add(new ApiStruct("ke_probe", null, [], [
        new ApiField("held", "ke_probe_kind", [], null),
        new ApiField("addressed", "ke_probe_body *", [], null),
    ], [])),
    contains: ["held: ke_probe_kind,",
               "pub const ke_probe_body = opaque {};",
               "addressed: *ke_probe_body,"],
    absent: ["pub const ke_probe_kind = opaque {};"]);

// A failure crosses the ABI in two spellings and neither reaches the caller's signature.
// A ke_error_type ** is the channel a handler reports through, so it becomes Zig's error
// union and the trampoline writes the singleton the error names; a ke_error_type * is a
// failure that already happened, so it becomes an optional error read the other way. The
// lane is optional either way, because succeeding is what a null in it means.
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

// A vtable the caller implements needs no interface declared for it: each slot becomes a
// method looked up on the caller's own type, so a missing or mistyped one is named by the
// Zig compiler. The state field is found by its type, and the plain fields the vtable also
// carries become parameters, so nothing about the value is left for the caller to fill.
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

if (failures.Count > 0)
{
    foreach (var f in failures) Console.Error.WriteLine($"  {f}");
    Console.Error.WriteLine($"{failures.Count} of {checks} Zig shape(s) are not what the backend emits.");
    return 1;
}

Console.WriteLine($"The Zig backend emits all {checks} declared shape(s).");
return 0;
