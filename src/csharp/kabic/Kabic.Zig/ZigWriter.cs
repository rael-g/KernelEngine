namespace Kabic.Zig;

using System.Text;

using Kabic;

/// <summary>
/// kabic's Zig writer: renders the ABI of one contract domain as a Zig module of extern
/// records, enum constants, callback types and opaque handles, laid out as the header lays
/// them out. A type another domain declares is reached through that domain's module, so a
/// type is one Zig type wherever it is used. A pointer says whether it reaches one value or
/// many from the header's tags, and stays nullable, as every C pointer is. Every member defaults
/// to zero. Rendering throws
/// <see cref="NotSupportedException"/> naming a declaration it cannot lay out.
/// </summary>
public sealed class ZigWriter
{
    readonly ApiModel model;
    readonly IReadOnlyDictionary<string, string> foreign;
    readonly SortedSet<string> imported = [];
    readonly HashSet<string> local;
    readonly bool factory;
    readonly FieldTableContext? tables;
    bool usesStd;

    ZigWriter(ApiModel model, IReadOnlyDictionary<string, string> foreign, bool factory, FieldTableContext? tables)
    {
        this.model = model;
        this.foreign = foreign;
        this.factory = factory;
        this.tables = tables;
        local = [
            .. model.Structs.Where(s => !s.External).Select(s => s.Name),
            .. model.Enums.Where(e => !e.External).Select(e => e.Name),
            .. model.TypeAliases.Keys,
            .. model.Opaques.Where(o => !foreign.ContainsKey(o)),
        ];
    }

    /// <summary>
    /// Renders the headers of one include root. <paramref name="foreign"/> maps each type
    /// another root declares to the name that root's module is imported as; a type found in
    /// neither this model nor the map is refused. A contract declares no function; the factory
    /// headers of a plugin, when <paramref name="factory"/> is set, declare each function the
    /// plugin exports, which the module declares as external.
    /// </summary>
    public static string Render(ApiModel model, IReadOnlyDictionary<string, string> foreign, bool factory = false,
        FieldTableContext? tables = null) =>
        new ZigWriter(model, foreign, factory, tables).Render();

    /// <summary>
    /// What the writer needs to lay out the field tables a header defines: the convention that
    /// names their entry and variant types and describes each field, the record of every name
    /// any root declares, and the root's model composed with the declarations of every other
    /// root, external, which the convention reads a field's shape from.
    /// </summary>
    public sealed record FieldTableContext(Convention Convention, IReadOnlyDictionary<string, ApiStruct> Records, ApiModel Composed);

    /// <summary>
    /// The components whose field table the headers of <paramref name="model"/> define, each
    /// with the name of its table.
    /// </summary>
    public static IEnumerable<(ApiStruct Component, string Table)> TablesOf(ApiModel model, Convention convention) =>
        convention.FieldTable is null ? [] : FieldTables.Describable(model, convention)
            .Select(s => (s, s.Name + "_fields")).Where(t => model.Statics.Contains(t.Item2));

    string Render()
    {
        var body = new StringBuilder();

        foreach (var name in model.Opaques.Where(o => !foreign.ContainsKey(o)).Order(StringComparer.Ordinal))
            body.AppendLine($"pub const {name} = opaque {{}};");
        if (model.Opaques.Count > 0) body.AppendLine();

        foreach (var (alias, target) in model.TypeAliases.OrderBy(kv => kv.Key, StringComparer.Ordinal))
        {
            if (model.CallbackOf(alias) is not null) continue;
            body.AppendLine($"pub const {alias} = {Spell(target, null)};");
        }
        if (model.TypeAliases.Count > 0) body.AppendLine();

        foreach (var c in model.Constants) RenderConstant(body, c);
        if (model.Constants.Count > 0) body.AppendLine();

        foreach (var e in model.Enums.Where(e => !e.External)) RenderEnum(body, e);

        foreach (var c in model.Callbacks)
        {
            Doc(body, c.Doc, "");
            body.AppendLine($"pub const {c.Name} = {FnPointer(c.Lanes.Select(l => (l.Type, (ApiParam?)l)), c.Returns, null)};");
            body.AppendLine();
        }

        foreach (var s in model.Structs.Where(s => !s.External))
        {
            Doc(body, s.Doc, "");
            body.AppendLine($"pub const {s.Name} = {Record(s, "")};");
            body.AppendLine();
        }

        if (tables is not null)
            foreach (var (component, table) in TablesOf(tables.Composed, tables.Convention)) RenderTable(body, component, table);

        var refused = model.Functions.Where(_ => !factory).Select(f => f.Name).Concat(model.Variables.Select(v => v.Name)).ToList();
        if (refused.Count > 0)
            throw new NotSupportedException(
                $"a contract declares vtable shapes only, and this one declares " + string.Join(", ", refused));

        foreach (var f in model.Functions.Where(_ => factory))
        {
            Doc(body, f.Doc, "");
            var ps = f.Params.Select((p, i) => $"{Ident(p.Name ?? $"arg{i}")}: {Spell(p.Type, Lane.Of(p))}");
            body.AppendLine($"pub extern fn {f.Name}({string.Join(", ", ps)}) {Spell(f.Returns, null)};");
            body.AppendLine();
        }

        var head = new StringBuilder();
        head.AppendLine("//! <auto-generated/> The ABI of the contract headers, laid out as they lay it out. Do not edit; edit the C header instead.");
        head.AppendLine();
        if (usesStd) head.AppendLine("const std = @import(\"std\");");
        foreach (var module in imported) head.AppendLine($"const {module} = @import(\"{module}\");");
        if (usesStd || imported.Count > 0) head.AppendLine();
        return head.Append(body).ToString().TrimEnd('\n').ReplaceLineEndings("\n") + "\n";
    }

    /// <summary>
    /// The field table of one component, entry by entry as the C table lists them: the key a
    /// scene writes, the variant kind, the member's offset and size, and its default.
    /// </summary>
    void RenderTable(StringBuilder sb, ApiStruct component, string table)
    {
        var convention = tables!.Convention;
        var t = convention.FieldTable!;
        var entry = tables.Records[t.EntryType].Fields.Select(f => Ident(f.Name)).ToList();
        sb.AppendLine($"pub const {table} = [_]{Named(t.EntryType, byValue: true)}{{");
        foreach (var f in FieldTables.Fields(tables.Composed, component, convention))
            sb.AppendLine($"    .{{ .{entry[0]} = \"{FieldTables.KeyOf(f)}\", .{entry[1]} = {Value(t.Variants[FieldTables.KindOf(tables.Composed, f, convention)!].Constant)}, "
                + $".{entry[2]} = @offsetOf({component.Name}, \"{f.Name}\"), .{entry[3]} = @sizeOf(@FieldType({component.Name}, \"{f.Name}\")), "
                + $".{entry[4]} = {Variant(f)} }},");
        sb.AppendLine("};");
        sb.AppendLine();
    }

    string Variant(ApiField f)
    {
        var convention = tables!.Convention;
        var t = convention.FieldTable!;
        var variant = tables.Records[t.VariantType].Fields;
        var kind = Ident(variant[0].Name);
        if (FieldTables.DefaultOf(tables.Composed, f, convention) is not { } d) return $".{{ .{kind} = {Value(t.Variants["null"].Constant)} }}";
        var member = t.Variants[d.Kind].Member.TrimStart('.');
        var payload = variant[1].Inline!.Fields.First(m => m.Name == member);
        var value = d.Kind switch
        {
            "string" => $"\"{d.Raw}\"",
            "bool" => d.Raw is "1" or "true" ? "true" : "false",
            "int" => d.Raw,
            "float" => ZigFloat(d.Lanes[0]),
            _ => ".{ " + string.Join(", ", tables.Records[Bare(payload.Type)].Fields.Zip(d.Lanes, (l, v) => $".{Ident(l.Name)} = {ZigFloat(v)}")) + " }",
        };
        return $".{{ .{kind} = {Value(t.Variants[d.Kind].Constant)}, .{Ident(variant[1].Name)} = .{{ .{Ident(member)} = {value} }} }}";
    }

    static string ZigFloat(string raw) => raw.Contains('.') ? raw : raw + ".0";

    /// <summary>A value an enum or a macro of this root or of another defines, reached as a type is.</summary>
    string Value(string name) =>
        model.Enums.Any(e => !e.External && e.Values.Any(v => v.Name == name)) || model.Constants.Any(c => c.Name == name)
            ? name : Named(name, byValue: true);

    /// <summary>
    /// One C enum as the integer type C gives it and a constant per value. A value is a
    /// constant rather than a case because the ABI carries the integer: a caller compares a
    /// value it may not know, which a Zig enum cannot hold.
    /// </summary>
    void RenderEnum(StringBuilder sb, ApiEnum e)
    {
        var signed = e.Values.Any(v => v.IsInt && long.Parse(v.RawValue) < 0);
        Doc(sb, e.Doc, "");
        sb.AppendLine($"pub const {e.Name} = {(signed ? "c_int" : "c_uint")};");
        foreach (var v in e.Values)
        {
            Doc(sb, v.Doc, "");
            sb.AppendLine($"pub const {v.Name}: {e.Name} = {v.RawValue};");
        }
        sb.AppendLine();
    }

    /// <summary>
    /// One macro constant. An integer the header types through a declared type keeps that type;
    /// one typed by C alone is a Zig integer literal, so its width is never one platform's.
    /// </summary>
    void RenderConstant(StringBuilder sb, ApiConstant c)
    {
        Doc(sb, c.Doc, "");
        if (c.Fields is { } fields)
            sb.AppendLine($"pub const {c.Name}: {Spell(c.Type, null)} = .{{ {string.Join(", ", fields.Select(f => $".{Ident(f.Name)} = {f.Value}"))} }};");
        else if (c.Type == "const char *" || Primitives.ContainsKey(Bare(c.Type)))
            sb.AppendLine($"pub const {c.Name} = {c.Value};");
        else
            sb.AppendLine($"pub const {c.Name}: {Spell(c.Type, null)} = {c.Value};");
    }

    /// <summary>
    /// A record as an extern struct or union, members in declaration order. A slot reads as a
    /// nullable function pointer whose first parameter is its receiver.
    /// </summary>
    string Record(ApiStruct s, string indent)
    {
        var sb = new StringBuilder();
        sb.AppendLine(s.IsUnion ? "extern union {" : "extern struct {");
        var members = s.Order ?? [.. s.Fields.Select(f => f.Name), .. s.Slots.Select(sl => sl.Name)];
        foreach (var name in members)
        {
            try { Member(sb, s, name, indent + "    "); }
            catch (NotSupportedException e) { throw new NotSupportedException($"{s.Name}.{name}: {e.Message}"); }
        }
        sb.Append(indent).Append('}');
        return sb.ToString();
    }

    void Member(StringBuilder sb, ApiStruct s, string name, string inner)
    {
        if (s.Fields.FirstOrDefault(f => f.Name == name) is { } f)
        {
            Doc(sb, f.Doc, inner);
            var type = f.Inline is { } record ? Record(record, inner) : Spell(f.Type, Lane.Of(f));
            sb.AppendLine(s.IsUnion ? $"{inner}{Ident(f.Name)}: {type}," : $"{inner}{Ident(f.Name)}: {type} = {Zero(f, type)},");
            return;
        }
        var slot = s.Slots.First(sl => sl.Name == name);
        Doc(sb, slot.Doc, inner);
        var lanes = slot.Params.Select(p => (p.Type, (ApiParam?)p))
            .Prepend((slot.Receiver ?? $"{s.Name} *", null));
        sb.AppendLine($"{inner}{Ident(slot.Name)}: {FnPointer(lanes, slot.Returns, slot.ReturnTagValue("array_of") is not null ? Lane.Many : null)} = null,");
    }

    /// <summary>
    /// The default of a struct member, since a union member takes none: zero, as C gives a member an initializer leaves out, so a
    /// params struct written with only the members it sets selects every other default.
    /// </summary>
    string Zero(ApiField field, string type)
    {
        if (field.Inline is not { } record) { usesStd = true; return $"std.mem.zeroes({type})"; }
        if (!record.IsUnion) return ".{}";
        var first = record.Fields[0];
        return $".{{ .{Ident(first.Name)} = {Zero(first, first.Inline is not null ? "" : Spell(first.Type, Lane.Of(first)))} }}";
    }

    string FnPointer(IEnumerable<(string Type, ApiParam? Param)> lanes, string returns, Lane? returned) =>
        $"?*const fn ({string.Join(", ", lanes.Select(l => Spell(l.Type, Lane.Of(l.Param))))}) callconv(.c) "
        + Spell(returns, returned);

    /// <summary>
    /// What the tags of a declaration say about the pointer it holds: whether it reaches one
    /// value or the first of many.
    /// </summary>
    sealed record Lane(bool IsMany)
    {
        public static readonly Lane Many = new(true);

        public static Lane? Of(ApiParam? p) => p is not null && p.Has("array_of") ? Many : null;

        public static Lane? Of(ApiField f) => f.Has("array_of") ? Many : null;
    }

    /// <summary>
    /// The Zig spelling of a C type. A fixed extent moves to the front, where Zig writes it.
    /// Every pointer level is nullable; the outermost reaches many values when the tags say
    /// so, and a pointer to <c>const char</c> is a terminated string unless they do.
    /// </summary>
    string Spell(string cType, Lane? lane)
    {
        if (CTypes.FixedArray(cType) is { } arr)
            return $"[{arr.Extent}]{Spell(arr.Element, null)}";
        if (model.CallbackOf(cType) is not null) return cType.Trim();
        if (CTypes.FunctionPointer(cType) is { Returns: { } returns } fn)
            return FnPointer(fn.ParamTypes.Select(t => (t, (ApiParam?)null)), returns, null);

        var levels = cType.Split('*');
        var bare = Bare(levels[0]);
        var depth = levels.Length - 1;
        if (depth == 0) return Named(bare, byValue: true);

        var spelled = (IsConst(levels[0]) ? "const " : "") + (bare == "void" ? "anyopaque" : Named(bare, byValue: false));
        for (var level = 1; level <= depth; level++)
        {
            var many = level == depth && lane is { IsMany: true };
            var marker = level == 1 && bare == "char" && IsConst(levels[0]) && !many ? "[*:0]"
                : level == 1 && bare == "void" ? "*"
                : many ? "[*]" : "*";
            spelled = $"?{marker}{spelled}";
            if (level < depth && IsConst(levels[level])) spelled = "const " + spelled;
        }
        return spelled;
    }

    static bool IsConst(string declarator) =>
        declarator.Split(' ', StringSplitOptions.RemoveEmptyEntries).Contains("const");

    static string Bare(string cType) =>
        cType.Replace("const", " ").Replace("volatile", " ").Replace("struct ", " ").Replace("union ", " ")
            .Replace("enum ", " ").Split(' ', StringSplitOptions.RemoveEmptyEntries) is var words
            ? string.Join(' ', words) : cType;

    string Named(string bare, bool byValue)
    {
        if (Primitives.TryGetValue(bare, out var prim)) return prim;
        if (local.Contains(bare)) return bare;
        if (foreign.TryGetValue(bare, out var module))
        {
            imported.Add(module);
            return $"{module}.{bare}";
        }
        throw new NotSupportedException(
            byValue
                ? $"{bare} is held by value and no domain describes it"
                : $"{bare} is pointed at and no domain declares it");
    }

    static readonly Dictionary<string, string> Primitives = new()
    {
        ["_Bool"] = "bool",
        ["bool"] = "bool",
        ["char"] = "u8",
        ["signed char"] = "i8",
        ["unsigned char"] = "u8",
        ["uint8_t"] = "u8",
        ["int8_t"] = "i8",
        ["uint16_t"] = "u16",
        ["int16_t"] = "i16",
        ["uint32_t"] = "u32",
        ["int32_t"] = "i32",
        ["uint64_t"] = "u64",
        ["int64_t"] = "i64",
        ["float"] = "f32",
        ["double"] = "f64",
        ["size_t"] = "usize",
        ["uintptr_t"] = "usize",
        ["intptr_t"] = "isize",
        ["void"] = "void",
        ["int"] = "c_int",
        ["unsigned"] = "c_uint",
        ["unsigned int"] = "c_uint",
        ["long"] = "c_long",
        ["unsigned long"] = "c_ulong",
        ["long long"] = "c_longlong",
        ["unsigned long long"] = "c_ulonglong",
    };

    static readonly HashSet<string> Reserved = [
        "addrspace", "align", "allowzero", "and", "anyframe", "anytype", "asm", "break", "callconv",
        "catch", "comptime", "const", "continue", "defer", "else", "enum", "errdefer", "error",
        "export", "extern", "fn", "for", "if", "inline", "linksection", "noalias", "noinline",
        "nosuspend", "opaque", "or", "orelse", "packed", "pub", "resume", "return", "struct",
        "suspend", "switch", "test", "threadlocal", "try", "type", "union", "unreachable", "var",
        "volatile", "while", "bool", "void", "true", "false", "null", "undefined",
    ];

    static string Ident(string name) =>
        Reserved.Contains(name) || IsPrimitiveTypeName(name) ? $"@\"{name}\"" : name;

    static bool IsPrimitiveTypeName(string name) =>
        name.Length > 1 && (name[0] is 'u' or 'i' or 'f') && name[1..].All(char.IsAsciiDigit)
        || name is "isize" or "usize" or "anyopaque" or "noreturn" or "comptime_int" or "comptime_float"
        || name.StartsWith("c_", StringComparison.Ordinal) && Primitives.ContainsValue(name);

    static void Doc(StringBuilder sb, string? doc, string indent)
    {
        if (doc is null) return;
        var words = doc.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        var line = new StringBuilder();
        foreach (var w in words)
        {
            if (line.Length > 0 && line.Length + w.Length > 92) { sb.AppendLine($"{indent}/// {line}"); line.Clear(); }
            if (line.Length > 0) line.Append(' ');
            line.Append(w);
        }
        if (line.Length > 0) sb.AppendLine($"{indent}/// {line}");
    }
}
