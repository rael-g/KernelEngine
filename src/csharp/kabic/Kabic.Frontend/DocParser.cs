// kabic's frontend: clang's Doxygen-lite comment AST.
//
// @param tags carry a leading `[tag1,tag2]` block, which is this codebase's
// only annotation vocabulary (docs/ScriptingArchitectureV3.md §5.2) — nothing
// downstream should ever need __attribute__((annotate(...))) again.

using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace Kabic.Frontend;

public static class DocParser
{
    static readonly Regex TagBlock = new(@"^\s*\[([^\]]+)\]\s*");

    public static (List<string> SummaryTags, string Summary, Dictionary<string, (List<string> Tags, string Doc)> Params, string ReturnDoc)
        Parse(JsonObject? node)
    {
        var summary = new List<string>();
        var paramChunks = new Dictionary<string, List<string>>();
        var returnChunks = new List<string>();

        void Walk(JsonObject n, List<string> sink)
        {
            var kind = n["kind"]?.GetValue<string>();
            if (kind == "ParamCommandComment")
            {
                var pname = n["param"]?.GetValue<string>() ?? "";
                sink = paramChunks.TryGetValue(pname, out var existing) ? existing
                     : paramChunks[pname] = [];
            }
            else if (kind == "BlockCommandComment" && n["name"]?.GetValue<string>() == "return")
            {
                sink = returnChunks;
            }
            else if (kind == "TextComment")
            {
                sink.Add(n["text"]?.GetValue<string>() ?? "");
            }
            if (n["inner"] is JsonArray inner)
                foreach (var c in inner) Walk(c!.AsObject(), sink);
        }

        var full = node?["inner"]?.AsArray().FirstOrDefault(c => c!["kind"]?.GetValue<string>() == "FullComment");
        if (full is not null) Walk(full.AsObject(), summary);

        (List<string> Tags, string Doc) SplitTags(List<string> chunks)
        {
            var raw = string.Join(' ', chunks).Trim();
            var m = TagBlock.Match(raw);
            var tags = m.Success ? m.Groups[1].Value.Split(',').Select(t => t.Trim()).ToList() : [];
            if (m.Success) raw = TagBlock.Replace(raw, "", 1);
            return (tags, string.Join(' ', raw.Split(' ', StringSplitOptions.RemoveEmptyEntries)));
        }

        var pmap = paramChunks.ToDictionary(kv => kv.Key, kv => SplitTags(kv.Value));
        // A slot's own summary can lead with a [tag] block too — the same bracket
        // convention as @param, just describing the SLOT (e.g. [lifecycle:init]
        // on ke_window.on_initialize) rather than one of its parameters.
        var (summaryTags, summaryText) = SplitTags(summary);
        return (summaryTags, summaryText,
                pmap, string.Join(' ', string.Join(' ', returnChunks).Split(' ', StringSplitOptions.RemoveEmptyEntries)));
    }
}
