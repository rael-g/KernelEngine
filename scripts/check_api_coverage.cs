#!/usr/bin/env dotnet run

// Fails when a public header is described by nobody: not by kabic
// (scripts/api_domains.json), not by ClangSharp (a .rsp under src/csharp), and
// not by an explicit, reasoned exclusion below.
//
// Why this exists: adding a header is silent today. Nothing reports that a new
// contract reaches no language, so the failure surfaces much later as "the scene
// says X and nothing happens" — the same silent-failure class the field tables
// and the generator diagnostics were built to close.
//
// Deliberately NOT "is it in the kabic manifest": a header can legitimately be
// covered by the ClangSharp track instead (framework/components.h is, and kabic
// would emit nothing for it). Asking about the kabic manifest alone reports
// covered headers as holes, which is how a gate gets ignored.
//
// Usage: dotnet run scripts/check_api_coverage.cs

using System.Runtime.CompilerServices;
using System.Text.Json.Nodes;

static string ScriptDir([CallerFilePath] string path = "") => Path.GetDirectoryName(path)!;
var rootDir = Path.GetFullPath(Path.Combine(ScriptDir(), ".."));

// A header nobody binds, with the reason it stays that way. Each entry is a
// decision on record — the point of the gate is that this list is the only place
// "not described" is allowed to be true, and that it has to be written down.
var excluded = new Dictionary<string, string>
{
    ["common/export.h"]                 = "visibility macros, no declarations",
    ["common/common_export.h"]          = "visibility macros, no declarations",
    ["logger/logger_export.h"]          = "visibility macros, no declarations",
    ["input/input_export.h"]            = "visibility macros, no declarations",
    ["resource_cache/resource_cache_export.h"] = "visibility macros, no declarations",
    ["render/gpu/gpu_commands.h"]       = "L4 command surface, rebuilt per backend rather than bound once (named debt)",
    ["render/gpu/gpu_surface_ext.h"]    = "platform surface handoff, consumed only by a backend's own Zig",
    ["render/service/pass_context.h"]   = "pass-internal; a pass is native, no managed caller",
    ["framework/scene_hierarchy.h"]     = "systems registered by the framework itself, nothing to call",

    // A render pass is created by render_module.zig and driven by the runtime;
    // no managed caller ever names one, so binding its factory would generate a
    // P/Invoke nobody can legally call.
    ["framework/scene_hierarchy_create.h"] = "created by the framework itself, no managed caller",
    ["render/cluster/cluster_create.h"] = "render pass factory, called only by render_module",
    ["render/deferred_lighting/deferred_lighting_create.h"] = "render pass factory, called only by render_module",
    ["render/forward/forward_create.h"] = "render pass factory, called only by render_module",
    ["render/gbuffer/gbuffer_create.h"] = "render pass factory, called only by render_module",
    ["render/service/render_service_create.h"] = "created by render_module, which hands back the borrowed service",
    ["render/shadow/shadow_create.h"] = "render pass factory, called only by render_module",
    ["render/skybox/skybox_create.h"] = "render pass factory, called only by render_module",
    ["render/tonemap/tonemap_create.h"] = "render pass factory, called only by render_module",
};

var manifest = JsonNode.Parse(File.ReadAllText(Path.Combine(rootDir, "scripts", "api_domains.json")))!.AsObject();

var describedByKabic = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
foreach (var d in manifest["domains"]!.AsArray())
    foreach (var key in (string[])["headers", "auxHeaders", "composeHeaders"])
        foreach (var h in d![key]?.AsArray() ?? [])
            describedByKabic.Add(Norm(h!.GetValue<string>()));

// A .rsp names headers as bare arguments after --file/--traverse; both mean the
// generator reads that header, which is what coverage asks about.
var describedByClangSharp = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
foreach (var rsp in Directory.EnumerateFiles(Path.Combine(rootDir, "src", "csharp"), "*.rsp", SearchOption.AllDirectories))
{
    var dir = Path.GetDirectoryName(rsp)!;
    foreach (var line in File.ReadAllLines(rsp))
    {
        var t = line.Trim();
        if (!t.EndsWith(".h", StringComparison.OrdinalIgnoreCase)) continue;
        describedByClangSharp.Add(Norm(Path.GetFullPath(Path.Combine(dir, t))));
    }
    // An umbrella header is a .rsp's own file, listing the domain's headers.
    foreach (var umbrella in Directory.EnumerateFiles(dir, "*.umbrella.h"))
        foreach (var line in File.ReadAllLines(umbrella))
            if (line.TrimStart().StartsWith("#include <", StringComparison.Ordinal))
                describedByClangSharp.Add(Norm(line.Trim()[10..].TrimEnd('>')));
}

var holes = new List<string>();
foreach (var dir in (string[])["src/c", "src/zig"])
    foreach (var header in Directory.EnumerateFiles(Path.Combine(rootDir, dir), "*.h", SearchOption.AllDirectories))
    {
        if (!header.Replace('\\', '/').Contains("/kernel_engine/")) continue;
        if (header.Contains(".zig-cache")) continue;
        var key = Norm(header);
        if (describedByKabic.Contains(key) || describedByClangSharp.Contains(key)) continue;
        if (excluded.ContainsKey(key)) continue;
        // A generated table is derived from a header already accounted for.
        if (Path.GetFileName(header) == "component_fields.h") continue;
        holes.Add(Path.GetRelativePath(rootDir, header).Replace('\\', '/'));
    }

if (holes.Count == 0)
{
    Console.WriteLine("Every public header is described by kabic, by ClangSharp, or by a recorded exclusion.");
    return 0;
}

Console.Error.WriteLine($"{holes.Count} header(s) reach no language:");
foreach (var h in holes.Order()) Console.Error.WriteLine($"  {h}");
Console.Error.WriteLine();
Console.Error.WriteLine("Add each to scripts/api_domains.json, to a .rsp, or to this script's");
Console.Error.WriteLine("exclusion list with the reason it stays unbound.");
return 1;

// Keyed on the path below kernel_engine/, so the same header names the same
// entry whether it was reached from the manifest (repo-relative), a .rsp
// (relative to the .rsp), or an umbrella's #include (include-relative).
static string Norm(string path)
{
    var p = path.Replace('\\', '/');
    var i = p.IndexOf("kernel_engine/", StringComparison.Ordinal);
    return i >= 0 ? p[(i + "kernel_engine/".Length)..] : p;
}
