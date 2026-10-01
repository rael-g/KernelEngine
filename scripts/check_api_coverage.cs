#!/usr/bin/env dotnet run

using System.Runtime.CompilerServices;
using System.Text.Json.Nodes;

static string ScriptDir([CallerFilePath] string path = "") => Path.GetDirectoryName(path)!;
var rootDir = Path.GetFullPath(Path.Combine(ScriptDir(), ".."));

var excluded = new Dictionary<string, string>
{
    ["common/export.h"]                 = "visibility macros, no declarations",
    ["common/common_export.h"]          = "visibility macros, no declarations",
    ["resource_cache/default/resource_cache_default_create.h"] = "created natively by plugins, no managed caller",
    ["render/gpu/gpu_commands.h"]       = "L4 command surface, rebuilt per backend rather than bound once (named debt)",
    ["render/gpu/gpu_surface_ext.h"]    = "platform surface handoff, consumed only by a backend's own Zig",
    ["render/service/pass_context.h"]   = "pass-internal; a pass is native, no managed caller",
    ["framework/scene_hierarchy.h"]     = "systems registered by the framework itself, nothing to call",

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
        if (Path.GetFileName(header) == "component_fields.h") continue;
        if (IsInlineOnly(header)) continue;
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

/// <summary>
/// True when a header declares nothing a binding could reach: every function it
/// defines is <c>static inline</c>, so there is no symbol to import and no vtable to
/// project. Derived rather than listed, so a new header-only helper does not have to
/// remember to register itself as an exception.
/// </summary>
static bool IsInlineOnly(string header)
{
    var declaresSomething = false;
    foreach (var raw in File.ReadAllLines(header))
    {
        var line = raw.Trim();
        if (line.StartsWith("static inline", StringComparison.Ordinal)) continue;
        if (line.StartsWith("typedef", StringComparison.Ordinal)
            || line.StartsWith("struct ", StringComparison.Ordinal)
            || line.StartsWith("enum ", StringComparison.Ordinal)
            || line.Contains("_API ", StringComparison.Ordinal)
            || line.Contains("(*", StringComparison.Ordinal))
        {
            declaresSomething = true;
            break;
        }
    }
    return !declaresSomething;
}

static string Norm(string path)
{
    var p = path.Replace('\\', '/');
    var i = p.IndexOf("kernel_engine/", StringComparison.Ordinal);
    return i >= 0 ? p[(i + "kernel_engine/".Length)..] : p;
}
