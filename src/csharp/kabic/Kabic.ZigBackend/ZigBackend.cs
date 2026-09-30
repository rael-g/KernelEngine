namespace Kabic.Zig;

using Kabic;
using System.Text;

/// <summary>
/// kabic's Zig backend: renders a domain as a Zig module — the ABI declared in Zig
/// rather than imported from the header, and a projection over it whose signatures
/// are Zig's own (error unions, optionals, slices, sentinel-terminated strings).
/// </summary>
/// <remarks>
/// <para>
/// Declares the ABI instead of reaching for <c>@cImport</c> on purpose. Importing
/// the header is what makes a Zig consumer feel it is calling a C library: every
/// pointer arrives as <c>[*c]</c>, which is both nullable and many-item, so the
/// compiler stops distinguishing "one value" from "an array" and stops catching a
/// missing null check. A declared ABI says which of the two each pointer is, and
/// the projection above it can then be total rather than defensive.
/// </para>
/// <para>
/// Emits no <c>comptime</c> machinery. The projection is one wrapper struct per
/// vtable with plain methods, which is the shape a C programmer reading Zig would
/// write. Whether a richer rendering is worth it is a question for after the
/// signatures are right, not before.
/// </para>
/// </remarks>
public sealed class ZigBackend
{
    readonly ApiModel model;
    readonly ClassifiedModel classified;
    readonly Convention convention;
    readonly IReadOnlyDictionary<string, ForeignType> foreign;
    readonly SortedDictionary<string, string> imported = [];
    readonly SortedSet<string> opaque = [];

    ZigBackend(ApiModel model, ClassifiedModel classified, Convention convention,
        IReadOnlyDictionary<string, ForeignType> foreign)
    {
        this.model = model;
        this.classified = classified;
        this.convention = convention;
        this.foreign = foreign;
    }

    /// <summary>
    /// Renders one domain. <paramref name="foreign"/> says where a type this domain
    /// composes but does not declare is reachable from: the domain that owns a type
    /// emits it, this one imports it. Zig has no ambient namespace for such a name to
    /// resolve in, so a domain rendered without the map spells a symbol its module
    /// never declares.
    /// </summary>
    public static string Render(ApiModel model, ClassifiedModel classified, Convention convention,
        IReadOnlyDictionary<string, ForeignType>? foreign = null) =>
        new ZigBackend(model, classified, convention, foreign ?? new Dictionary<string, ForeignType>())
            .Render();

    string Render()
    {
        var sb = new StringBuilder();
        var abi = new StringBuilder();

        foreach (var (alias, target) in model.TypeAliases)
        {
            var prim = Idioms.Primitive(target);
            if (prim is not null) sb.AppendLine($"pub const {Idioms.TypeName(alias, convention)} = {prim};");
        }
        sb.AppendLine();

        foreach (var e in model.Enums.Where(e => !e.External)) RenderEnum(sb, e);

        sb.AppendLine(Preamble);

        sb.AppendLine("/// The ABI as the header declares it. Nothing above this line is a C name and");
        sb.AppendLine("/// nothing below it is meant to be called by hand.");
        foreach (var c in model.Callbacks)
            abi.AppendLine($"    pub const {c.Name} = ?*const fn ({string.Join(", ", c.Lanes.Select(l =>
                $"{Idioms.Ident(l.Name ?? "_")}: {AbiType(l.Type, l, "")}"))}) "
                + $"callconv(.c) {AbiType(c.Returns, null, "")};");
        if (model.Callbacks.Count > 0) abi.AppendLine();
        foreach (var s in model.Structs.Where(s => !s.External))
        {
            abi.AppendLine($"    pub const {s.Name} = extern struct {{");
            foreach (var f in s.Fields)
                abi.AppendLine($"        {Idioms.Ident(f.Name)}: {AbiType(f.Type, null, "")},");
            foreach (var slot in s.Slots)
                abi.AppendLine($"        {Idioms.Ident(slot.Name)}: *const fn ({SlotAbiParams(s, slot)})"
                    + $" callconv(.c) {AbiReturn(slot, "")},");
            abi.AppendLine("    };");
            abi.AppendLine();
        }
        foreach (var f in model.Functions)
            abi.AppendLine($"    pub extern fn {f.Name}({string.Join(", ", f.Params.Select(p =>
                $"{Idioms.Ident(p.Name ?? "_")}: {AbiType(p.Type, p, "")}"))}) "
                + $"callconv(.c) {AbiType(f.Returns, null, "")};");

        var projections = new StringBuilder();
        foreach (var v in classified.Providers)
            RenderProvider(projections, v);

        sb.AppendLine("pub const abi = struct {");
        sb.AppendLine(AbiPreamble);
        sb.Append(AbiErrorTypes);
        foreach (var name in opaque)
        {
            sb.AppendLine("    /// No domain describes this type, so the only thing known about it here is");
            sb.AppendLine("    /// that its address travels. A field of it that ought to be reachable means");
            sb.AppendLine("    /// the header declaring it is missing from this domain's description.");
            sb.AppendLine($"    pub const {name} = opaque {{}};");
        }
        if (opaque.Count > 0) sb.AppendLine();
        sb.Append(abi);
        sb.AppendLine("};");
        sb.AppendLine();
        sb.Append(projections);

        var head = new StringBuilder();
        head.AppendLine("//! <auto-generated/> Derived from ke_api.json. Do not edit; edit the C header instead.");
        head.AppendLine();
        foreach (var (module, path) in imported)
            head.AppendLine($"const {module} = @import(\"{path}\");");
        if (imported.Count > 0) head.AppendLine();
        return head.Append(sb).ToString();
    }

    /// <summary>
    /// One C enum as a Zig enum. A member whose C initialiser names a sibling is not a
    /// case of its own: it is a second name for one that already exists, so it is
    /// rendered as a declaration rather than a field. Zig refuses two fields sharing a
    /// tag value, so the alternative is not a duplicated case but no output at all --
    /// and emitting the C initialiser verbatim would name a symbol the Zig module does
    /// not declare.
    /// </summary>
    void RenderEnum(StringBuilder sb, ApiEnum e)
    {
        if (e.Doc is not null) foreach (var line in DocLines(e.Doc)) sb.AppendLine(line);
        sb.AppendLine($"pub const {Idioms.TypeName(e.Name, convention)} = enum(u32) {{");
        foreach (var v in e.Values.Where(v => v.IsInt))
        {
            if (v.Doc is not null) foreach (var line in DocLines(v.Doc, "    ")) sb.AppendLine(line);
            sb.AppendLine($"    {Idioms.EnumMember(v.Name, e.Name)} = {v.RawValue},");
        }
        foreach (var v in e.Values.Where(v => !v.IsInt))
        {
            if (v.Doc is not null) foreach (var line in DocLines(v.Doc, "    ")) sb.AppendLine(line);
            sb.AppendLine($"    pub const {Idioms.EnumMember(v.Name, e.Name)}: @This() = "
                + $".{Idioms.EnumMember(v.RawValue, e.Name)};");
        }
        sb.AppendLine("};");
        sb.AppendLine();
    }

    /// <summary>
    /// The kinds the error hierarchy names, paired with the singleton each is reached by.
    /// One list because three functions have to agree about it: the set a caller catches,
    /// the reading of a failure the engine reported, and the writing of one the caller's
    /// own handler raised. Kept apart, a kind added to one of them is a kind the other two
    /// silently flatten to <c>General</c>.
    /// </summary>
    static readonly (string Kind, string Singleton)[] ErrorKinds = [
        ("NotFound", "KE_ERROR_NOT_FOUND"),
        ("Io", "KE_ERROR_IO"),
        ("OutOfMemory", "KE_ERROR_OUT_OF_MEMORY"),
        ("InvalidArgument", "KE_ERROR_INVALID_ARGUMENT"),
        ("NotInitialized", "KE_ERROR_NOT_INITIALIZED"),
        ("NotSupported", "KE_ERROR_NOT_SUPPORTED"),
        ("AlreadyExists", "KE_ERROR_ALREADY_EXISTS"),
    ];

    /// <summary>
    /// The error vocabulary every module opens with: the set, the thread-local carrying
    /// what a Zig error set cannot, and the three crossings between the two spellings.
    /// </summary>
    static string Preamble
    {
        get
        {
            var sb = new StringBuilder(PreambleHead);
            sb.AppendLine("pub const Error = error{");
            sb.AppendLine("    General,");
            foreach (var (kind, _) in ErrorKinds) sb.AppendLine($"    {kind},");
            sb.AppendLine("};");
            sb.AppendLine();

            sb.AppendLine("fn raise(err: ?*const abi.ke_error) Error {");
            sb.AppendLine("    last_error = err;");
            foreach (var (kind, singleton) in ErrorKinds)
                sb.AppendLine($"    if (abi.ke_error_is(err, &abi.{singleton})) return Error.{kind};");
            sb.AppendLine("    return Error.General;");
            sb.AppendLine("}");
            sb.AppendLine();

            sb.AppendLine(ErrorTypeDoc);
            sb.AppendLine("fn errorType(e: Error) *const abi.ke_error_type {");
            sb.AppendLine("    return switch (e) {");
            foreach (var (kind, singleton) in ErrorKinds)
                sb.AppendLine($"        Error.{kind} => &abi.{singleton},");
            sb.AppendLine("        else => &abi.KE_ERROR_GENERAL,");
            sb.AppendLine("    };");
            sb.AppendLine("}");
            sb.AppendLine();

            sb.AppendLine(ErrorFromDoc);
            sb.AppendLine("fn errorFrom(t: ?*const abi.ke_error_type) ?Error {");
            sb.AppendLine("    const named = t orelse return null;");
            foreach (var (kind, singleton) in ErrorKinds)
                sb.AppendLine($"    if (named == &abi.{singleton}) return Error.{kind};");
            sb.AppendLine("    return Error.General;");
            sb.AppendLine("}");
            sb.AppendLine();
            return sb.ToString();
        }
    }

    const string ErrorTypeDoc = """
        /// The singleton a Zig error is reported to the engine as. A handler the engine
        /// calls has to name its failure in the vocabulary the ABI reads, and a type is
        /// the only half of a failure that outlives the thread that raised it.
        """;

    const string ErrorFromDoc = """
        /// The Zig error a reported type names. Compared by address, because the types are
        /// immortal singletons and there is nothing else to compare; a kind this module
        /// does not name -- including a subtype of one it does -- reads as General, since
        /// narrowing it would mean walking a parent chain the caller cannot act on.
        """;

    const string PreambleHead = """
        /// The failure a fallible call reported. A Zig error set carries a kind and
        /// nothing else, so the message, the source location and the cause chain the
        /// native side filled in have to be readable somewhere; thread-local for the
        /// same reason the native slot is, which is that two threads failing at once
        /// are two failures.
        pub threadlocal var last_error: ?*const abi.ke_error = null;

        """;

    /// <summary>
    /// The types <see cref="AbiPreamble"/> declares by hand. They reach a description as
    /// names no domain owns, so without this the error channel itself would be taken for
    /// a type nobody describes.
    /// </summary>
    static readonly HashSet<string> AbiPreambleTypes = ["ke_error", "ke_error_type"];

    const string AbiPreamble = """
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

        """;

    /// <summary>
    /// The singletons the projection reaches, declared from the one list that also builds
    /// the error set. <c>KE_ERROR_GENERAL</c> is not among the kinds, because it is what a
    /// failure reads as when no kind matched rather than a kind a caller catches by name.
    /// </summary>
    static string AbiErrorTypes =>
        string.Concat(ErrorKinds.Select(k => k.Singleton).Prepend("KE_ERROR_GENERAL")
            .Select(s => $"    pub extern const {s}: ke_error_type;\n")) + "\n";

    /// <summary>
    /// The slot's parameters with its receiver put back. The receiver is not always
    /// the struct that declares the slot -- an owner wrapper's <c>destroy</c> takes
    /// the value the wrapper holds -- so it is read from the description rather than
    /// assumed, because a declaration naming the wrong pointer type still compiles.
    /// </summary>
    string SlotAbiParams(ApiStruct owner, ApiSlot slot)
    {
        var receiver = slot.Receiver is { } declared
            ? AbiType(declared, null, "")
            : $"*{owner.Name}";
        return string.Join(", ", new[] { $"self: {receiver}" }
            .Concat(slot.Params.Select(p =>
                $"{Idioms.Ident(p.Name ?? "_")}: {AbiType(p.Type, p, "")}")));
    }

    string AbiReturn(ApiSlot slot, string q) =>
        slot.ReturnTagValue("array_of") is not null
            ? $"?[*]const {AbiType(CTypes.Deref(slot.Returns), null, q)}"
            : AbiType(slot.Returns, null, q);

    /// <summary>
    /// The Zig spelling of a C type. Every pointer answers two questions C leaves
    /// open — may it be null, and does it reach one value or many — and the answers
    /// come from the tags, which is the whole reason this is not <c>@cImport</c>.
    /// A fixed extent moves to the front, where Zig writes it, and the element type
    /// goes on through the same mapping: an extent left as a C declarator suffix
    /// would take the whole spelling off the primitive table with it.
    /// </summary>
    string AbiType(string cType, ApiParam? p, string q)
    {
        if (CTypes.FixedArray(cType) is { } arr)
            return $"[{arr.Extent}]{AbiType(arr.Element, p, q)}";

        var t = Idioms.Base(cType);
        var isConst = cType.Contains("const ");
        var depth = t.Count(ch => ch == '*');
        var bare = t.TrimEnd('*', ' ').Trim();

        if (depth == 0) return Named(bare, q);
        if (bare is "void") return depth == 1 ? "?*anyopaque" : "*?*anyopaque";
        if (bare is "char" && depth == 1) return "[*:0]const u8";

        var inner = Pointee(bare, q);
        var cv = isConst ? "const " : "";
        if (depth == 2) return $"?*?*{cv}{inner}";
        if (p is not null && p.Has("array_of")) return $"[*]{cv}{inner}";
        return p is not null && (p.Has("optional") || IsOutcome(p))
            ? $"?*{cv}{inner}" : $"*{cv}{inner}";
    }

    /// <summary>
    /// The type a pointer points at. A name no domain describes is a C type forward
    /// declared and never defined -- a handle the header hands out and the caller only
    /// ever holds the address of. Zig says that with <c>opaque</c>, and saying it is
    /// what makes the pointer legal: spelling the bare name instead leaves the module
    /// naming a symbol nothing declares. Only reachable behind a pointer, because a
    /// value of a layout this domain cannot see is a defect in the description rather
    /// than a type to invent.
    /// </summary>
    string Pointee(string bare, string q)
    {
        var named = Named(bare, q);
        if (named == q + bare && !AbiPreambleTypes.Contains(bare)
            && !DeclaredHere(bare) && !model.Structs.Any(s => s.Name == bare))
            opaque.Add(bare);
        return named;
    }

    string Named(string bare, string q)
    {
        if (Idioms.Primitive(bare) is { } prim && !model.TypeAliases.ContainsKey(bare)) return prim;
        if (!DeclaredHere(bare) && foreign.TryGetValue(bare, out var owner))
        {
            var binding = Bind(owner.Module);
            imported[binding] = owner.ImportPath;
            return owner.IsStruct
                ? $"{binding}.abi.{bare}"
                : $"{binding}.{Idioms.TypeName(bare, convention)}";
        }
        if (model.TypeAliases.TryGetValue(bare, out var target) && Idioms.Primitive(target) is not null)
            return Idioms.TypeName(bare, convention);
        if (model.Enums.Any(e => e.Name == bare)) return Idioms.TypeName(bare, convention);
        if (model.Structs.Any(s => s.Name == bare)) return q + bare;
        return Idioms.Primitive(bare) ?? q + bare;
    }

    /// <summary>
    /// The name an imported module is bound to. A domain reached for one of its types is
    /// named after itself, unless this module already declares that name -- a vtable with
    /// an <c>ecs</c> slot projects a method of that name, and a reference to <c>ecs</c>
    /// inside the projection would then reach two declarations at once, which Zig refuses
    /// rather than resolves.
    /// </summary>
    string Bind(string module) =>
        LocalNames.Contains(module) ? module + "_domain" : module;

    /// <summary>
    /// Every name this module puts in scope around a call into the ABI: its own top-level
    /// declarations, the methods of its projections, and those methods' parameters. All of
    /// them see a top-level binding, so all of them can shadow one -- and a parameter is
    /// the case worth renaming the import for rather than the other way round, because the
    /// parameter's name is the header's own word for it and the binding's is invented.
    /// </summary>
    HashSet<string> LocalNames => localNames ??= [
        .. model.TypeAliases.Keys.Select(a => Idioms.TypeName(a, convention)),
        .. model.Enums.Select(e => Idioms.TypeName(e.Name, convention)),
        .. classified.Providers.Select(v => Idioms.TypeName(v.Name, convention)),
        .. classified.Providers.SelectMany(v => classified.SlotsByVtable[v.Name])
            .Select(cs => Idioms.Camel(cs.Slot.Name)),
        .. classified.Providers.SelectMany(v => classified.SlotsByVtable[v.Name])
            .SelectMany(cs => cs.Slot.Params).Where(p => p.Name is not null)
            .Select(p => Idioms.Ident(p.Name!)),
    ];

    HashSet<string>? localNames;

    /// <summary>
    /// Whether this domain declares the type itself. A type reaching the model marked
    /// external, or reaching it only as the spelling of a field, is declared by some
    /// other domain -- which is exactly the case an import answers.
    /// </summary>
    bool DeclaredHere(string bare) =>
        model.Structs.Any(s => s.Name == bare && !s.External)
        || model.Enums.Any(e => e.Name == bare && !e.External)
        || model.TypeAliases.ContainsKey(bare);

    /// <summary>The Zig type a projected value reads as, outside the ABI block.</summary>
    string PubType(string cType, ApiParam? p) =>
        AbiType(cType, p, "abi.");

    void RenderProvider(StringBuilder sb, ApiStruct v)
    {
        var name = Idioms.TypeName(v.Name, convention);
        if (v.Doc is not null) foreach (var line in DocLines(v.Doc)) sb.AppendLine(line);
        sb.AppendLine($"pub const {name} = struct {{");
        sb.AppendLine($"    ref: *abi.{v.Name},");
        sb.AppendLine($"    destroy: ?*const fn (self: *abi.{v.Name}) callconv(.c) void,");
        sb.AppendLine();
        sb.AppendLine($"    pub fn init(handle: abi.{convention.HandleTypeFor(v.Name)}) {name} {{");
        sb.AppendLine("        return .{ .ref = handle.ref, .destroy = handle.destroy };");
        sb.AppendLine("    }");
        sb.AppendLine();
        sb.AppendLine("    /// Wraps a native pointer owned elsewhere. Deinit does not destroy it.");
        sb.AppendLine($"    pub fn borrow(ref: *abi.{v.Name}) {name} {{");
        sb.AppendLine("        return .{ .ref = ref, .destroy = null };");
        sb.AppendLine("    }");
        sb.AppendLine();
        sb.AppendLine($"    pub fn deinit(self: *{name}) void {{");
        sb.AppendLine("        if (self.destroy) |d| d(self.ref);");
        sb.AppendLine("        self.destroy = null;");
        sb.AppendLine("    }");

        var declared = classified.SlotsByVtable[v.Name]
            .Select(cs => Idioms.Camel(cs.Slot.Name)).ToHashSet();
        declared.UnionWith(["init", "borrow", "deinit", "ref", "destroy"]);

        foreach (var cs in classified.SlotsByVtable[v.Name])
        {
            sb.AppendLine();
            RenderSlot(sb, cs, name, declared);
        }
        sb.AppendLine("};");
        sb.AppendLine();
    }

    record Reading(string Name, string Type, string Expr);

    /// <summary>
    /// One slot as a method on the projection. <paramref name="declared"/> is what the
    /// projection struct already declares: Zig refuses a parameter that shadows an
    /// outer declaration, and a vtable with both a <c>parent</c> slot and a
    /// <c>parent</c> parameter is not a mistake in the header -- the two names live in
    /// different scopes in C, and only the projection puts them in the same one.
    /// </summary>
    void RenderSlot(StringBuilder sb, ClassifiedSlot cs, string owner, IReadOnlySet<string> declared)
    {
        string Arg(ApiParam p) =>
            Idioms.Ident(declared.Contains(p.Name!) ? p.Name! + "_arg" : p.Name!);

        var slot = cs.Slot;
        if (cs.Blobs.Count > 0 || cs.ExpandedParam is not null
            || slot.Params.Any(p => (model.CallbackOf(p.Type) is not null || p.Has("callback"))
                && !p.Has("closure")))
            throw new NotSupportedException(
                $"{slot.Name}: this backend renders no raw callback, no [expand] and no opaque payload yet.");

        var closures = slot.Params.Where(p => p.Has("closure"))
            .Select(p => Closure(slot, p)).ToList();
        var closureOf = closures.ToDictionary(c => c.Fn);
        var stateOf = closures.ToDictionary(c => c.State);

        var outs = (cs.Shape switch
        {
            SlotShape.Try or SlotShape.TupleOutParams => cs.OutParams,
            SlotShape.ReturnsOutParam => [cs.OutParam!],
            _ => cs.TrailingOuts,
        }).Where(p => !IsWritableSpan(p)).ToList();
        var errParam = cs.Fallible ? slot.Params[^1] : null;
        var counts = cs.Sequences.Select(s => s.Count).ToHashSet();

        var sig = cs.PublicParams.Where(p => !p.Has("out") || IsWritableSpan(p)).ToList();
        var body = new List<string>();
        var args = new List<string> { "self.ref" };

        foreach (var p in slot.Params)
        {
            if (p == errParam) { args.Add("&err"); continue; }
            if (closureOf.TryGetValue(p, out var fnOf)) { args.Add($"{TrampolineName(fnOf)}.call"); continue; }
            if (stateOf.ContainsKey(p)) { args.Add($"@ptrCast({Arg(p)})"); continue; }
            if (counts.Contains(p)) { args.Add($"@intCast({Arg(cs.Sequences.First(s => s.Count == p).Seq)}.len)"); continue; }
            if (p == cs.ReturnCount) { args.Add("&count"); continue; }
            if (p.Has("array_of")) { args.Add($"{Arg(p)}.ptr"); continue; }
            if (p.Has("out")) { args.Add("&" + Local(p)); continue; }
            if (p.Has("utf8")) { args.Add($"{Arg(p)}.ptr"); continue; }
            args.Add(Arg(p));
        }

        var taken = slot.Params.Where(p => p.Name is not null).Select(Arg)
            .Append("self").Concat(declared).ToHashSet();
        foreach (var c in closures) body.AddRange(TrampolineLines(c, Arg(c.Fn), taken));

        foreach (var p in outs)
            body.Add($"var {Local(p)}: "
                + $"{PubType(CTypes.Deref(p.Type), null)} = undefined;");
        if (cs.ReturnCount is not null) body.Add("var count: u32 = 0;");
        if (cs.Fallible) body.Add("var err: ?*abi.ke_error = null;");

        var call = $"self.ref.{Idioms.Ident(slot.Name)}({string.Join(", ", args)})";

        var readings = outs.Select(p => new Reading(WrittenName(p),
            PubType(CTypes.Deref(p.Type), null),
            Local(p))).ToList();

        var returnIsFailureLane = convention.SignalsFailureByReturn(slot.Returns)
            && (cs.Fallible || cs.Shape is SlotShape.Try);
        var carriesReturn = slot.Returns.Trim() is not "void" && !returnIsFailureLane;
        string? valueType = null;
        if (cs.ReturnCount is not null)
            valueType = $"[]const {PubType(CTypes.Deref(slot.Returns), null)}";
        else if (carriesReturn)
            valueType = PubType(slot.Returns, null);

        var items = (valueType is null ? readings : readings.Prepend(new Reading("value", valueType, "result"))).ToList();
        var inner = items.Count switch
        {
            0 => "void",
            1 => items[0].Type,
            _ => "struct { " + string.Join(", ", items.Select(i => $"{Idioms.Ident(i.Name)}: {i.Type}")) + " }",
        };
        var ret = cs.Shape is SlotShape.Try ? $"?{inner}" : cs.Fallible ? $"Error!{inner}" : inner;

        string Compose() => items.Count switch
        {
            0 => "return;",
            1 => $"return {items[0].Expr};",
            _ => "return .{ " + string.Join(", ", items.Select(i => $".{Idioms.Ident(i.Name)} = {i.Expr}")) + " };",
        };

        if (cs.ReturnCount is not null)
        {
            body.Add($"const front = {call} orelse return &.{{}};");
            body.Add("return front[0..count];");
        }
        else if (cs.Shape is SlotShape.Try)
        {
            body.Add($"if (!{call}) return null;");
            body.Add(Compose());
        }
        else if (cs.Fallible && convention.SignalsFailureByReturn(slot.Returns))
        {
            body.Add($"if (!{call}) return raise(err);");
            body.Add(Compose());
        }
        else if (carriesReturn)
        {
            body.Add($"const result = {call};");
            if (cs.Fallible) body.Add("if (err != null) return raise(err);");
            body.Add(Compose());
        }
        else
        {
            body.Add($"{call};");
            body.Add(Compose());
        }

        if (slot.Doc is not null) foreach (var line in DocLines(slot.Doc, "    ")) sb.AppendLine(line);
        var sigText = string.Join(", ", new[] { $"self: {owner}" }
            .Concat(sig.Where(p => !stateOf.ContainsKey(p)).SelectMany(p =>
                closureOf.TryGetValue(p, out var c)
                    ? new[] { $"{Arg(c.State)}: anytype", $"comptime {Arg(p)}: {HandlerType(c, Arg(c.State))}" }
                    : [$"{Arg(p)}: {SigType(p)}"])));
        sb.AppendLine($"    pub fn {Idioms.Camel(slot.Name)}({sigText}) {ret} {{");
        foreach (var line in body) sb.AppendLine($"        {line}");
        sb.AppendLine("    }");
    }

    /// <summary>
    /// A handler the caller supplies, the state it reaches its own data through, and the
    /// lanes of the typedef that says how the engine will call it.
    /// </summary>
    record ClosureForm(ApiParam Fn, ApiParam State, ApiCallback Callback,
        ApiParam ContextLane, ApiParam? ErrorLane, ReportKind Report,
        IReadOnlyList<ApiParam> OutcomeLanes);

    /// <summary>
    /// How a handler tells the engine it failed. The two spellings are not
    /// interchangeable: a <c>ke_error</c> points into the failing thread's own storage and
    /// there is no exported way to mint one, so that channel can only carry the fact of a
    /// failure and the kind is lost; a <c>ke_error_type</c> is an immortal singleton, so
    /// that one carries the kind whole.
    /// </summary>
    enum ReportKind { None, Fact, Kind }

    static string Norm(string t) => t.Replace(" ", "");

    static ReportKind ReportOf(ApiParam lane) => Norm(lane.Type) switch
    {
        "ke_error**" => ReportKind.Fact,
        "constke_error_type**" => ReportKind.Kind,
        _ => ReportKind.None,
    };

    /// <summary>
    /// Whether the lane tells the handler that something already failed. That is the
    /// opposite direction from a report channel, and it reads as an optional error rather
    /// than one, because the engine calls the handler on success too.
    /// </summary>
    static bool IsOutcome(ApiParam lane) =>
        Norm(lane.Type) is "constke_error*" or "constke_error_type*";

    /// <summary>
    /// The closure a <c>[closure:&lt;state&gt;]</c> parameter declares. Which lane carries
    /// the caller's own pointer back is the typedef's own statement, because a lane typed
    /// <c>void*</c> says nothing about what travels in it.
    /// </summary>
    ClosureForm Closure(ApiSlot slot, ApiParam fn)
    {
        var where = $"{slot.Name}.{fn.Name}";
        var stateName = fn.TagValue("closure")
            ?? throw new NotSupportedException(
                $"{where}: [closure] must name the state parameter, as [closure:<name>]");
        var state = slot.Params.FirstOrDefault(p => p.Name == stateName)
            ?? throw new NotSupportedException(
                $"{where}: [closure:{stateName}] names no parameter of this slot");
        var callback = model.CallbackOf(fn.Type)
            ?? throw new NotSupportedException(
                $"{where}: [closure] needs a function-pointer typedef, and {fn.Type.Trim()} is not one");
        var context = callback.Lanes.FirstOrDefault(l => l.Has("context"))
            ?? throw new NotSupportedException(
                $"{where}: {callback.Name} declares no [context] lane for the state to return in");
        if (callback.Lanes.Any(l => l.Has("self") || l.Has("ctx")))
            throw new NotSupportedException(
                $"{where}: {callback.Name} hands the handler an engine object, which this backend"
                + " does not project yet");
        var report = callback.Lanes.FirstOrDefault(l => ReportOf(l) is not ReportKind.None);
        return new ClosureForm(fn, state, callback, context, report,
            report is null ? ReportKind.None : ReportOf(report),
            callback.Lanes.Where(IsOutcome).ToList());
    }

    /// <summary>
    /// The function the caller writes. The context lane is gone -- the state arrives
    /// typed, so there is nothing to cast back -- a lane the typedef declares as a report
    /// channel becomes Zig's own error union, and a lane naming a failure that already
    /// happened becomes an optional error. Nothing in the signature spells
    /// <c>ke_error</c>, which is the point: both spellings are the ABI's way of saying
    /// something Zig already has a way of saying.
    /// </summary>
    string HandlerType(ClosureForm c, string stateArg)
    {
        var lanes = c.Callback.Lanes
            .Where(l => l != c.ContextLane && l != c.ErrorLane)
            .Select(HandlerLaneType)
            .Prepend($"@TypeOf({stateArg})");
        var ret = c.Report is not ReportKind.None ? "Error!void"
            : c.Callback.Returns.Trim() is "void" ? "void"
            : PubType(c.Callback.Returns, null);
        return $"fn ({string.Join(", ", lanes)}) {ret}";
    }

    string HandlerLaneType(ApiParam lane) =>
        IsOutcome(lane) ? "?Error"
        : lane.Has("utf8") ? "[:0]const u8"
        : PubType(lane.Type, lane);

    static string TrampolineName(ClosureForm c) => Idioms.Pascal(c.Fn.Name!) + "Trampoline";

    /// <summary>
    /// The optional error an outcome lane reads as. A <c>ke_error</c> goes through the
    /// same reading a fallible call uses, so the message and the cause chain stay
    /// reachable; a <c>ke_error_type</c> has no such storage to record, which is the whole
    /// reason the ABI chose it for a failure that outlives its thread.
    /// </summary>
    static string OutcomeExpr(ApiParam lane, string name) =>
        Norm(lane.Type) is "constke_error*"
            ? $"if ({name}) |failed| raise(failed) else null"
            : $"errorFrom({name})";

    /// <summary>
    /// The C entry point the engine is handed. Zig closes over nothing at runtime, so
    /// the state travels the same <c>void*</c> lane C uses and comes back a typed
    /// pointer -- which is why nothing here has to be retained: the memory is the
    /// caller's, and outliving the call is their statement to make, not a table's.
    /// <paramref name="taken"/> is what the method around it already names: a lane and a
    /// parameter may share a name in C, where they are two prototypes, and the trampoline
    /// is the one place that nests one inside the other.
    /// </summary>
    IEnumerable<string> TrampolineLines(ClosureForm c, string handler, IReadOnlySet<string> taken)
    {
        string Lane(ApiParam l) => l == c.ErrorLane && c.Report is ReportKind.Fact ? "_"
            : Idioms.Ident(taken.Contains(l.Name!) ? l.Name! + "_lane" : l.Name!);
        var ps = c.Callback.Lanes.Select(l => $"{Lane(l)}: {PubType(l.Type, l)}");
        var ctx = $"@ptrCast(@alignCast({Lane(c.ContextLane)}.?))";
        var handed = c.Callback.Lanes.Where(l => l != c.ContextLane && l != c.ErrorLane)
            .Select(l => IsOutcome(l) ? OutcomeExpr(l, Lane(l))
                : l.Has("utf8") ? Within("std", $"std.mem.span({Lane(l)})")
                : Lane(l));
        var call = $"{handler}({string.Join(", ", new[] { ctx }.Concat(handed))})";
        var ret = PubType(c.Callback.Returns, null);

        yield return $"const {TrampolineName(c)} = struct {{";
        yield return $"    fn call({string.Join(", ", ps)}) callconv(.c) {ret} {{";
        if (c.Report is ReportKind.Kind)
        {
            yield return $"        {call} catch |e| {{";
            yield return $"            if ({Lane(c.ErrorLane!)}) |slot| slot.* = errorType(e);";
            if (ret is not "void") yield return "            return false;";
            yield return "        };";
            if (ret is not "void") yield return "        return true;";
        }
        else if (c.Report is ReportKind.Fact)
        {
            yield return $"        {call} catch return false;";
            yield return "        return true;";
        }
        else if (c.Callback.Returns.Trim() is "void") yield return $"        {call};";
        else yield return $"        return {call};";
        yield return "    }";
        yield return "};";
    }

    /// <summary>
    /// Records that the module reaches <paramref name="module"/>, and gives back the
    /// expression unchanged. An import Zig never sees used is a compile error, so the
    /// only place that can say a module is needed is the one that spells it.
    /// </summary>
    string Within(string module, string expr)
    {
        imported[module] = module;
        return expr;
    }

    /// <summary>
    /// How a supplied parameter is spelled in the projection. A counted pointer is
    /// one slice, a utf8 string is one sentinel-terminated slice, and in both cases
    /// the length the ABI takes separately comes off the value itself.
    /// </summary>
    string SigType(ApiParam p)
    {
        if (p.Has("utf8")) return "[:0]const u8";
        if (p.Has("array_of"))
            return (IsWritableSpan(p) ? "[]" : "[]const ") + PubType(CTypes.Deref(p.Type), null);
        return PubType(p.Type, p);
    }

    /// <summary>
    /// Whether a parameter is a buffer the caller allocates and the callee fills. It
    /// is written back, like any <c>[out]</c>, and it is also counted, which is what
    /// says the count is the caller's -- so there is nothing here to declare a local
    /// for and take the address of: the value already is the memory, and the span
    /// carries the capacity the ABI asks for separately.
    /// </summary>
    static bool IsWritableSpan(ApiParam p) => p.Has("out") && p.Has("array_of");

    /// <summary>The local a written-back parameter's address is taken from.</summary>
    static string Local(ApiParam p) => Idioms.Ident(WrittenName(p) + "_out");

    static string WrittenName(ApiParam p) =>
        p.Name!.StartsWith("out_", StringComparison.Ordinal) && p.Name!.Length > 4
            ? p.Name!["out_".Length..] : p.Name!;

    static IEnumerable<string> DocLines(string doc, string indent = "")
    {
        var words = doc.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        var line = new StringBuilder();
        foreach (var w in words)
        {
            if (line.Length > 0 && line.Length + w.Length > 76) { yield return $"{indent}/// {line}"; line.Clear(); }
            if (line.Length > 0) line.Append(' ');
            line.Append(w);
        }
        if (line.Length > 0) yield return $"{indent}/// {line}";
    }
}
