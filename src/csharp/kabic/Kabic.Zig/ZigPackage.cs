namespace Kabic.Zig;

using System.Text;

using Kabic;

/// <summary>
/// The Zig package of the headers of one include root, a contract domain or a plugin's factory
/// headers: the module of their ABI under the name <c>abi</c>, the packages it imports as
/// dependencies, and a test that lays every record, alias, enum value and constant beside the
/// translation of the headers and fails where the two differ.
/// </summary>
/// <param name="Key">The name the package's module is imported under by the packages that
/// import it.</param>
/// <param name="Headers">The headers, relative to their include root.</param>
/// <param name="Imports">The packages whose types these headers compose.</param>
/// <param name="IncludeDirs">The include directories the headers are translated with, relative
/// to the package.</param>
/// <param name="Package">The package name its dependents declare.</param>
public sealed record ZigPackage(string Key, string Package, IReadOnlyList<string> Headers, IReadOnlyList<ZigImport> Imports,
    IReadOnlyList<string> IncludeDirs)
{
    /// <summary>The package name of the package of the contract domain <paramref name="domain"/>.</summary>
    public static string DomainPackage(string domain) => $"ke_abi_{domain}";

    /// <summary>The <c>build.zig</c> of the package.</summary>
    public string BuildZig()
    {
        var sb = new StringBuilder();
        sb.AppendLine("const std = @import(\"std\");");
        sb.AppendLine();
        sb.AppendLine("pub fn build(b: *std.Build) void {");
        sb.AppendLine("    const target = b.standardTargetOptions(.{});");
        sb.AppendLine("    const optimize = b.standardOptimizeOption(.{});");
        sb.AppendLine();
        sb.AppendLine($"    const abi = b.addModule(\"abi\", .{{ .root_source_file = b.path(\"{Key}.zig\") }});");
        foreach (var i in Imports)
            sb.AppendLine($"    abi.addImport(\"{i.Key}\", b.dependency(\"{i.Package}\", .{{}}).module(\"abi\"));");
        sb.AppendLine();
        sb.AppendLine("    const headers = b.addWriteFiles().add(\"layout.h\",");
        foreach (var h in Headers)
            sb.AppendLine($"        \\\\#include <{h}>");
        sb.AppendLine("    );");
        sb.AppendLine("    const translated = b.addTranslateC(.{ .root_source_file = headers, .target = target, .optimize = optimize });");
        foreach (var dir in IncludeDirs)
            sb.AppendLine($"    translated.addIncludePath(b.path(\"{dir}\"));");
        sb.AppendLine("    const tests = b.addTest(.{ .root_module = b.createModule(.{");
        sb.AppendLine("        .root_source_file = b.path(\"layout_test.zig\"),");
        sb.AppendLine("        .target = target,");
        sb.AppendLine("        .optimize = optimize,");
        sb.AppendLine("        .imports = &.{");
        sb.AppendLine("            .{ .name = \"abi\", .module = abi },");
        sb.AppendLine("            .{ .name = \"c\", .module = translated.createModule() },");
        sb.AppendLine("        },");
        sb.AppendLine("    }) });");
        sb.AppendLine($"    b.step(\"test\", \"Check the {Key} ABI against its headers\").dependOn(&b.addRunArtifact(tests).step);");
        sb.AppendLine("}");
        return sb.ToString();
    }

    /// <summary>
    /// The <c>build.zig.zon</c> of the package. Its fingerprint is derived from the name, so a
    /// regeneration writes the same one.
    /// </summary>
    public string BuildZon() => Zon(Package, Imports.Select(i => (i.Package, i.Path)));

    /// <summary>
    /// The layout test of the package: one check per record and alias, comparing size,
    /// alignment and the offset of every member, inline records included, one per enum
    /// value, one per macro constant, and one per field table among <paramref name="tables"/>,
    /// whose entries it compares member by member, a union's payload aside.
    /// </summary>
    public static string LayoutTest(ApiModel model, IReadOnlyList<string>? tables = null)
    {
        tables ??= [];
        var sb = new StringBuilder();
        sb.AppendLine("const std = @import(\"std\");");
        sb.AppendLine("const abi = @import(\"abi\");");
        sb.AppendLine("const c = @import(\"c\");");
        sb.AppendLine();
        sb.AppendLine("fn expectSameLayout(comptime A: type, comptime C: type) !void {");
        sb.AppendLine("    try std.testing.expectEqual(@sizeOf(C), @sizeOf(A));");
        sb.AppendLine("    try std.testing.expectEqual(@alignOf(C), @alignOf(A));");
        sb.AppendLine("    switch (@typeInfo(A)) {");
        sb.AppendLine("        .@\"struct\" => |s| inline for (s.fields) |f| {");
        sb.AppendLine("            try std.testing.expectEqual(@offsetOf(C, f.name), @offsetOf(A, f.name));");
        sb.AppendLine("            try expectSameLayout(f.type, @FieldType(C, f.name));");
        sb.AppendLine("        },");
        sb.AppendLine("        .@\"union\" => |u| inline for (u.fields) |f| try expectSameLayout(f.type, @FieldType(C, f.name)),");
        sb.AppendLine("        else => {},");
        sb.AppendLine("    }");
        sb.AppendLine("}");
        sb.AppendLine();
        sb.AppendLine("fn translated(comptime name: []const u8) type {");
        sb.AppendLine("    return if (@hasDecl(c, name)) @field(c, name) else @field(c, \"struct_\" ++ name);");
        sb.AppendLine("}");
        sb.AppendLine();
        sb.AppendLine("test \"every record is laid out as the header lays it out\" {");
        foreach (var s in model.Structs.Where(s => !s.External))
            sb.AppendLine($"    try expectSameLayout(abi.{s.Name}, translated(\"{s.Name}\"));");
        foreach (var (alias, _) in model.TypeAliases.OrderBy(kv => kv.Key, StringComparer.Ordinal))
            sb.AppendLine($"    try expectSameLayout(abi.{alias}, c.{alias});");
        sb.AppendLine("}");
        var values = model.Enums.Where(e => !e.External).SelectMany(e => e.Values).ToList();
        if (values.Count > 0)
        {
            sb.AppendLine();
            sb.AppendLine("test \"every enum value is the header's value\" {");
            foreach (var v in values)
                sb.AppendLine($"    try std.testing.expectEqual(@as(i64, c.{v.Name}), @as(i64, abi.{v.Name}));");
            sb.AppendLine("}");
        }
        if (tables.Count > 0)
        {
            sb.AppendLine();
            sb.AppendLine("fn expectSameValue(a: anytype, k: anytype) !void {");
            sb.AppendLine("    switch (@typeInfo(@TypeOf(a))) {");
            sb.AppendLine("        .@\"struct\" => |s| inline for (s.fields) |f| try expectSameValue(@field(a, f.name), @field(k, f.name)),");
            sb.AppendLine("        .@\"union\" => {},");
            sb.AppendLine("        .optional => try std.testing.expectEqualStrings(std.mem.span(k), std.mem.span(a.?)),");
            sb.AppendLine("        else => try std.testing.expectEqual(@as(@TypeOf(a), k), a),");
            sb.AppendLine("    }");
            sb.AppendLine("}");
            sb.AppendLine();
            sb.AppendLine("test \"every field table lists the header's entries\" {");
            foreach (var t in tables)
            {
                sb.AppendLine($"    try std.testing.expectEqual(c.{t}.len, abi.{t}.len);");
                sb.AppendLine($"    for (abi.{t}, c.{t}) |a, k| try expectSameValue(a, k);");
            }
            sb.AppendLine("}");
        }
        if (model.Constants.Count > 0)
        {
            sb.AppendLine();
            sb.AppendLine("test \"every constant is the header's value\" {");
            foreach (var k in model.Constants)
                sb.AppendLine(k.Fields is not null
                    ? $"    try std.testing.expectEqual(std.mem.toBytes(c.{k.Name}), std.mem.toBytes(abi.{k.Name}));"
                    : k.Type == "const char *"
                        ? $"    try std.testing.expectEqualStrings(c.{k.Name}, abi.{k.Name});"
                        : $"    try std.testing.expectEqual(@as(i128, c.{k.Name}), @as(i128, abi.{k.Name}));");
            sb.AppendLine("}");
        }
        return sb.ToString();
    }

    /// <summary>The package name of the package that gathers every package.</summary>
    public const string AllName = "ke_abi";

    /// <summary>
    /// The <c>build.zig</c> of the package that gathers every package: its <c>test</c> step runs
    /// every package's layout test.
    /// </summary>
    public static string AllBuildZig(IReadOnlyList<ZigImport> packages)
    {
        var sb = new StringBuilder();
        sb.AppendLine("const std = @import(\"std\");");
        sb.AppendLine();
        sb.AppendLine("pub fn build(b: *std.Build) void {");
        sb.AppendLine("    const target = b.standardTargetOptions(.{});");
        sb.AppendLine("    const optimize = b.standardOptimizeOption(.{});");
        sb.AppendLine("    const tests = b.step(\"test\", \"Check the ABI of every contract domain and factory header against the headers\");");
        sb.AppendLine("    inline for (.{");
        foreach (var p in packages) sb.AppendLine($"        \"{p.Package}\",");
        sb.AppendLine("    }) |name| {");
        sb.AppendLine("        const domain = b.dependency(name, .{ .target = target, .optimize = optimize });");
        sb.AppendLine("        tests.dependOn(&domain.builder.top_level_steps.get(\"test\").?.step);");
        sb.AppendLine("    }");
        sb.AppendLine("}");
        return sb.ToString();
    }

    /// <summary>The <c>build.zig.zon</c> of the package that gathers every package.</summary>
    public static string AllBuildZon(IReadOnlyList<ZigImport> packages) =>
        Zon(AllName, packages.Select(p => (p.Package, p.Path)));

    static string Zon(string name, IEnumerable<(string Name, string Path)> dependencies)
    {
        var sb = new StringBuilder();
        sb.AppendLine(".{");
        sb.AppendLine($"    .name = .{name},");
        sb.AppendLine("    .version = \"0.1.0\",");
        sb.AppendLine($"    .fingerprint = 0x{Fingerprint(name):x16},");
        sb.AppendLine("    .minimum_zig_version = \"0.16.0\",");
        sb.AppendLine("    .dependencies = .{");
        foreach (var (dep, path) in dependencies)
            sb.AppendLine($"        .{dep} = .{{ .path = \"{path}\" }},");
        sb.AppendLine("    },");
        sb.AppendLine("    .paths = .{\".\"},");
        sb.AppendLine("}");
        return sb.ToString();
    }

    /// <summary>
    /// A package fingerprint as Zig checks it: the CRC-32 of the name in the upper half and an
    /// identifier in the lower half that is neither zero nor all ones.
    /// </summary>
    static ulong Fingerprint(string name)
    {
        var checksum = Crc32(Encoding.UTF8.GetBytes(name));
        var id = Crc32(Encoding.UTF8.GetBytes("kernel_engine/" + name));
        if (id is 0 or uint.MaxValue) id = 1;
        return ((ulong)checksum << 32) | id;
    }

    static uint Crc32(byte[] bytes)
    {
        var crc = uint.MaxValue;
        foreach (var b in bytes)
        {
            crc ^= b;
            for (var k = 0; k < 8; k++) crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320u : crc >> 1;
        }
        return ~crc;
    }
}

/// <summary>
/// A package another one depends on: the name its module is imported under, its package name,
/// and its directory, relative to the dependent.
/// </summary>
public sealed record ZigImport(string Key, string Package, string Path);
