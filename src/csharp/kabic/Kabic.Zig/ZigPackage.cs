namespace Kabic.Zig;

using System.Text;

using Kabic;

/// <summary>
/// The Zig package of one contract domain: the module of its ABI under the name <c>abi</c>,
/// the domains it imports as dependencies, and a test that lays every record, alias and
/// enum value beside the translation of the domain's headers and fails where the two differ.
/// </summary>
/// <param name="Domain">The domain's directory name under the contracts root.</param>
/// <param name="Headers">The domain's headers, relative to its include directory.</param>
/// <param name="Imports">The domains whose types this one composes.</param>
/// <param name="IncludeDirs">The include directories the headers are translated with, relative
/// to the package.</param>
public sealed record ZigPackage(string Domain, IReadOnlyList<string> Headers, IReadOnlyList<string> Imports,
    IReadOnlyList<string> IncludeDirs)
{
    /// <summary>The package name its dependents declare.</summary>
    public static string PackageName(string domain) => $"ke_abi_{domain}";

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
        sb.AppendLine($"    const abi = b.addModule(\"abi\", .{{ .root_source_file = b.path(\"{Domain}.zig\") }});");
        foreach (var d in Imports)
            sb.AppendLine($"    abi.addImport(\"{d}\", b.dependency(\"{PackageName(d)}\", .{{}}).module(\"abi\"));");
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
        sb.AppendLine($"    b.step(\"test\", \"Check the {Domain} ABI against its headers\").dependOn(&b.addRunArtifact(tests).step);");
        sb.AppendLine("}");
        return sb.ToString();
    }

    /// <summary>
    /// The <c>build.zig.zon</c> of the package. Its fingerprint is derived from the name, so a
    /// regeneration writes the same one.
    /// </summary>
    public string BuildZon() => Zon(PackageName(Domain), Imports.Select(d => (PackageName(d), $"../{d}")));

    /// <summary>
    /// The layout test of the package: one check per record and alias, comparing size,
    /// alignment and the offset of every member, inline records included, and one per enum
    /// value.
    /// </summary>
    public static string LayoutTest(ApiModel model)
    {
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
        return sb.ToString();
    }

    /// <summary>The package name of the package that gathers every domain's.</summary>
    public const string AllName = "ke_abi";

    /// <summary>
    /// The <c>build.zig</c> of the package that gathers every domain's: its <c>test</c> step runs
    /// every domain's layout test.
    /// </summary>
    public static string AllBuildZig(IReadOnlyList<string> domains)
    {
        var sb = new StringBuilder();
        sb.AppendLine("const std = @import(\"std\");");
        sb.AppendLine();
        sb.AppendLine("pub fn build(b: *std.Build) void {");
        sb.AppendLine("    const target = b.standardTargetOptions(.{});");
        sb.AppendLine("    const optimize = b.standardOptimizeOption(.{});");
        sb.AppendLine("    const tests = b.step(\"test\", \"Check every contract domain's ABI against its headers\");");
        sb.AppendLine("    inline for (.{");
        foreach (var d in domains) sb.AppendLine($"        \"{PackageName(d)}\",");
        sb.AppendLine("    }) |name| {");
        sb.AppendLine("        const domain = b.dependency(name, .{ .target = target, .optimize = optimize });");
        sb.AppendLine("        tests.dependOn(&domain.builder.top_level_steps.get(\"test\").?.step);");
        sb.AppendLine("    }");
        sb.AppendLine("}");
        return sb.ToString();
    }

    /// <summary>The <c>build.zig.zon</c> of the package that gathers every domain's.</summary>
    public static string AllBuildZon(IReadOnlyList<string> domains) =>
        Zon(AllName, domains.Select(d => (PackageName(d), d)));

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
