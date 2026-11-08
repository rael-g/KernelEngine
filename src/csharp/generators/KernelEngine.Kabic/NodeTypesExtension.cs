using System.Text;

using Kabic;
using Kabic.Pipeline;

namespace KernelEngine.Kabic;

/// <summary>
/// Writes <c>engine_node_types.h</c>: a <c>ke_node_type_desc</c> for every component a header tags
/// <c>[node:]</c>, named after the component, carrying it and the components of its bases. The
/// table holds names only, so it includes no domain's header.
/// </summary>
public sealed class NodeTypesExtension : IKabicExtension
{
    const string Path = "src/c/framework/kernel_engine/framework/engine_node_types.h";
    const string Guard = "KERNEL_ENGINE_FRAMEWORK_ENGINE_NODE_TYPES_H_";

    /// <inheritdoc/>
    public string Name => "nodeTypes";

    /// <inheritdoc/>
    public void Run(ExtensionContext context)
    {
        var nodes = context.Domains.SelectMany(d => d.Model.Structs)
            .Where(s => !s.IsVtable && !s.External && s.Has("node") && s.Name.EndsWith("_component", StringComparison.Ordinal))
            .DistinctBy(s => s.Name)
            .OrderBy(s => s.Name, StringComparer.Ordinal)
            .ToList();
        var byNode = nodes.ToDictionary(s => s.TagValue("node")!);
        string ComponentName(ApiStruct s) => context.Convention.StripPrefix(s.Name)[..^"_component".Length];

        var o = new StringBuilder();
        o.Append($"#ifndef {Guard}\n#define {Guard}\n\n");
        o.Append("#include <kernel_engine/framework/node_types.h>\n\n");
        foreach (var s in nodes)
        {
            var with = new List<string>();
            for (var at = s; at is not null; at = at.TagValue("base") is { } b ? byNode.GetValueOrDefault(b) : null)
                with.Add($"\"{ComponentName(at)}\"");
            o.Append($"static const char *const ke_{ComponentName(s)}_node_with[] = {{ {string.Join(", ", with)} }};\n");
        }
        o.Append("\n/** Every node type the engine's components describe: a name and the components it carries. */\n");
        o.Append("static const ke_node_type_desc ke_engine_node_types[] = {\n");
        foreach (var s in nodes)
        {
            var name = ComponentName(s);
            var count = 0;
            for (var at = s; at is not null; at = at.TagValue("base") is { } b ? byNode.GetValueOrDefault(b) : null) count++;
            o.Append($"    {{ .name = \"{name}\", .with = ke_{name}_node_with, .with_count = {count} }},\n");
        }
        o.Append("};\n\n");
        o.Append($"#define KE_ENGINE_NODE_TYPE_COUNT {nodes.Count}\n\n#endif\n");
        context.Emit(Path, o.ToString());
    }
}
