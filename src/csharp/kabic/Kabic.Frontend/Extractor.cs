// kabic's frontend proper: walks a clang AST (from `zig cc -ast-dump=json`)
// into the SAME ApiModel that Kabic.Core's Classifier consumes — the reader
// and writer of ke_api.json share one model definition, so the schema cannot
// silently drift between the two sides the way two hand-kept-in-sync copies
// eventually would.

using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace Kabic.Frontend;

public static class Extractor
{
    public static (ApiModel Model, List<string> Errors) Extract(JsonObject ast, HashSet<string> headerNames,
        Dictionary<string, byte[]> sourceBytes, HashSet<string>? auxHeaderNames = null)
    {
        var api = new ApiModel();
        var errors = new List<string>();
        string? currentFile = null;
        auxHeaderNames ??= [];

        // clang's JSON AST is delta-encoded: loc.file (NOT includedFrom.file,
        // which names the *including* file and would misattribute every
        // declaration to the synthesized translation unit) appears only when
        // it changes from the previous node, so the current file has to be
        // carried forward across siblings.
        (bool Owned, bool AuxOnly, string? File) Owns(JsonObject node)
        {
            var f = node["loc"]?.AsObject()["file"]?.GetValue<string>();
            // Normalized once here so every downstream sourceBytes[file] lookup
            // matches regardless of whether clang echoed this particular include
            // as absolute, relative, or through a bind-mount prefix (observed to
            // vary run-to-run for the same header set) — the caller's sourceBytes
            // dictionary is keyed the same way. An unnormalized mismatch doesn't
            // throw; it silently falls back to the WRONG file's bytes, corrupting
            // every byte-offset slice (param names, enum literals) taken from it.
            if (f is not null) currentFile = Path.GetFullPath(f);
            if (currentFile is null) return (false, false, null);
            var fileName = Path.GetFileName(currentFile);
            var full = headerNames.Contains(fileName);
            var aux = !full && auxHeaderNames.Contains(fileName);
            return (full || aux, aux, currentFile);
        }

        var top = ast["inner"]!.AsArray();
        foreach (var nodeRaw in top)
        {
            var node = nodeRaw!.AsObject();
            var (owned, auxOnly, file) = Owns(node);
            if (!owned) continue;

            var kind = node["kind"]?.GetValue<string>();
            var name = node["name"]?.GetValue<string>();
            var bytes = file is not null && sourceBytes.TryGetValue(file, out var b) ? b : sourceBytes.Values.First();

            // A header pulled in purely so a foreign domain's typedef'd primitives
            // resolve (--aux) contributes ONLY those typedefs — its own vtables,
            // enums, and functions are somebody else's domain to describe, and
            // parsing them here just adds unused noise (and, empirically, a
            // flakier param-name extraction on declarations nothing here consumes).
            if (auxOnly && kind != "TypedefDecl") continue;

            switch (kind)
            {
                case "EnumDecl" when name is not null:
                    api.Enums.Add(ExtractEnum(node, name, bytes));
                    break;

                case "RecordDecl" when name is not null && node["completeDefinition"]?.GetValue<bool>() == true:
                    api.Structs.Add(ExtractStruct(node, name, bytes, errors));
                    break;

                case "FunctionDecl" when name is not null && name.StartsWith("ke_"):
                    api.Functions.Add(ExtractFunction(node, name, errors));
                    break;

                // A typedef naming a plain primitive (ke_entity -> uint64_t) is an
                // alias every backend must see through; one naming a struct or enum
                // is a real type the description already carries under its own key.
                case "TypedefDecl" when name is not null:
                {
                    var target = node["type"]?.AsObject()["qualType"]?.GetValue<string>() ?? "";
                    if (!target.StartsWith("struct ") && !target.StartsWith("enum ")
                        && !target.Contains('(') && target != name)
                        api.TypeAliases[name] = target;
                    break;
                }
            }
        }

        return (api, errors);
    }

    static ApiEnum ExtractEnum(JsonObject node, string name, byte[] bytes)
    {
        var values = new List<ApiEnumValue>();
        long next = 0;
        foreach (var c in (node["inner"] as JsonArray) ?? [])
        {
            var e = c!.AsObject();
            if (e["kind"]?.GetValue<string>() != "EnumConstantDecl") continue;
            var doc = DocParser.Parse(e).Summary;
            var literalText = SliceRange(bytes, e);
            var m = Regex.Match(literalText, @"=\s*(-?\w+)");
            string rawValue = next.ToString();
            var isInt = true;
            if (m.Success)
            {
                var tok = m.Groups[1].Value;
                isInt = Regex.IsMatch(tok, @"^-?\d+$");
                rawValue = isInt ? long.Parse(tok).ToString() : tok;
            }
            if (isInt) next = long.Parse(rawValue) + 1;
            values.Add(new ApiEnumValue(e["name"]!.GetValue<string>(), rawValue, isInt, doc.Length > 0 ? doc : null));
        }
        var enumDoc = DocParser.Parse(node).Summary;
        return new ApiEnum(name, enumDoc.Length > 0 ? enumDoc : null, values);
    }

    static ApiStruct ExtractStruct(JsonObject node, string name, byte[] bytes, List<string> errors)
    {
        var fields = new List<ApiField>();
        var slots = new List<ApiSlot>();

        foreach (var c in (node["inner"] as JsonArray) ?? [])
        {
            var f = c!.AsObject();
            if (f["kind"]?.GetValue<string>() != "FieldDecl") continue;
            var fieldName = f["name"]?.GetValue<string>();
            // An anonymous union/struct member has no name and no ABI-portable
            // description (which member is "active" isn't derivable from the type
            // alone) — skip it rather than crash; a consumer needing it stays on
            // the idiom layer, same as [raw_callback].
            if (fieldName is null)
            {
                Console.Error.WriteLine($"note: {name}: skipping unnamed field (anonymous union/struct) — "
                    + "not describable, handle in the idiom layer");
                continue;
            }
            var qual = f["type"]?.AsObject()["qualType"]?.GetValue<string>() ?? "";
            var (ret, paramTypes) = SplitFnPtr(qual);
            var (summaryTags, summary, pdocs, retDoc) = DocParser.Parse(f);

            if (ret is null)
            {
                fields.Add(new ApiField(fieldName, qual, summaryTags, summary.Length > 0 ? summary : null));
                continue;
            }

            var pnames = DeclText.FnPtrParamNames(bytes, fieldName);
            foreach (var tagged in pdocs.Keys)
            {
                if (!pnames.Contains(tagged))
                    errors.Add($"{name}.{fieldName}: @param '{tagged}' is not a parameter "
                        + $"(signature has {string.Join(", ", pnames.Skip(1).Where(n => n is not null))})");
            }

            var slotParams = new List<ApiParam>();
            for (var i = 1; i < paramTypes.Count; i++) // skip self (index 0)
            {
                var pname = i < pnames.Count ? pnames[i] : null;
                var (tags, doc) = pname is not null && pdocs.TryGetValue(pname, out var d)
                    ? (d.Tags, d.Doc) : ([], "");
                slotParams.Add(new ApiParam(pname, paramTypes[i], tags, doc.Length > 0 ? doc : null));
            }
            slots.Add(new ApiSlot(fieldName, ret, summaryTags, summary.Length > 0 ? summary : null,
                retDoc.Length > 0 ? retDoc : null, slotParams));
        }

        var (structTags, structDoc, _, _) = DocParser.Parse(node);
        return new ApiStruct(name, structDoc.Length > 0 ? structDoc : null, structTags, fields, slots);
    }

    static ApiFunction ExtractFunction(JsonObject node, string name, List<string> errors)
    {
        var (_, summary, pdocs, retDoc) = DocParser.Parse(node); // functions don't carry slot-shape tags today
        var paramDecls = ((node["inner"] as JsonArray) ?? [])
            .Where(c => c!["kind"]?.GetValue<string>() == "ParmVarDecl").Select(c => c!.AsObject()).ToList();
        var pnames = paramDecls.Select(p => p["name"]?.GetValue<string>()).ToList();

        foreach (var tagged in pdocs.Keys)
        {
            if (!pnames.Contains(tagged))
                errors.Add($"{name}: @param '{tagged}' is not a parameter (signature has {string.Join(", ", pnames)})");
        }

        var returns = (node["type"]?.AsObject()["qualType"]?.GetValue<string>() ?? "").Split('(')[0].Trim();
        var parameters = paramDecls.Select(p =>
        {
            var pname = p["name"]?.GetValue<string>() ?? "";
            var ptype = p["type"]?.AsObject()["qualType"]?.GetValue<string>() ?? "";
            var (tags, doc) = pdocs.TryGetValue(pname, out var d) ? (d.Tags, d.Doc) : ([], "");
            return new ApiParam(pname, ptype, tags, doc.Length > 0 ? doc : null);
        }).ToList();

        return new ApiFunction(name, returns, summary.Length > 0 ? summary : null,
            retDoc.Length > 0 ? retDoc : null, parameters);
    }

    static string SliceRange(byte[] bytes, JsonObject node)
    {
        var range = node["range"]?.AsObject();
        var b = range?["begin"]?.AsObject()["offset"]?.GetValue<int>();
        var e = range?["end"]?.AsObject()["offset"]?.GetValue<int>();
        var tokLen = range?["end"]?.AsObject()["tokLen"]?.GetValue<int>() ?? 1;
        if (b is null || e is null) return "";
        var end = Math.Min(e.Value + tokLen, bytes.Length);
        return System.Text.Encoding.UTF8.GetString(bytes, b.Value, end - b.Value);
    }

    static (string? Returns, List<string> ParamTypes) SplitFnPtr(string qual)
    {
        var i = qual.IndexOf("(*)", StringComparison.Ordinal);
        if (i < 0) return (null, []);
        var ret = qual[..i].Trim();
        var openParen = qual.IndexOf('(', i + 3);
        var body = qual[(openParen + 1)..qual.LastIndexOf(')')];
        var args = new List<string>();
        var depth = 0;
        var cur = "";
        foreach (var ch in body + ",")
        {
            if (ch == ',' && depth == 0) { if (cur.Trim().Length > 0) args.Add(cur.Trim()); cur = ""; }
            else { depth += ch == '(' ? 1 : 0; depth -= ch == ')' ? 1 : 0; cur += ch; }
        }
        return (ret, args);
    }
}
