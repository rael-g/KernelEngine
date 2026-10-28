
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace Kabic.Reader;

/// <summary>
/// Turns the AST of a translation unit into the declarations of an <c>ApiModel</c>, keeping only
/// those declared in the files the caller owns.
/// </summary>
public static class Extractor
{
    /// <summary>
    /// Extracts the declarations owned by the files named in the arguments, and returns them with
    /// the errors found on the way as messages.
    /// </summary>
    /// <param name="headerNames">Full paths of the files whose declarations are owned in full.</param>
    /// <param name="sourceBytes">The source text of each file, keyed by its full path.</param>
    /// <param name="auxHeaderNames">Full paths of the files whose typedefs alone are extracted.</param>
    /// <param name="composeHeaderNames">Full paths of the files whose typedefs, records and enums
    /// are extracted.</param>
    /// <param name="symbolPrefix">Only functions whose names start with this prefix are
    /// extracted.</param>
    public static (ApiModel Model, List<string> Errors) Extract(JsonObject ast, HashSet<string> headerNames,
        Dictionary<string, byte[]> sourceBytes, HashSet<string>? auxHeaderNames = null,
        HashSet<string>? composeHeaderNames = null, string symbolPrefix = "")
    {
        var api = new ApiModel();
        var errors = new List<string>();
        string? currentFile = null;
        auxHeaderNames ??= [];
        composeHeaderNames ??= [];

        (bool Owned, bool AuxOnly, bool Compose, string? File) Owns(JsonObject node)
        {
            var f = node["loc"]?.AsObject()["file"]?.GetValue<string>();
            if (f is not null) currentFile = Path.GetFullPath(f);
            if (currentFile is null) return (false, false, false, null);
            var full = headerNames.Contains(currentFile);
            var compose = !full && composeHeaderNames.Contains(currentFile);
            var aux = !full && !compose && auxHeaderNames.Contains(currentFile);
            return (full || aux || compose, aux, compose, currentFile);
        }

        var top = ast["inner"]!.AsArray();
        var defined = top.OfType<JsonObject>()
            .Where(n => n["kind"]?.GetValue<string>() == "RecordDecl" && n["completeDefinition"]?.GetValue<bool>() == true)
            .Select(n => n["name"]?.GetValue<string>()).OfType<string>().ToHashSet();
        foreach (var nodeRaw in top)
        {
            var node = nodeRaw!.AsObject();
            var (owned, auxOnly, compose, file) = Owns(node);
            if (!owned) continue;

            var kind = node["kind"]?.GetValue<string>();
            var name = node["name"]?.GetValue<string>();
            var bytes = file is not null && sourceBytes.TryGetValue(file, out var b) ? b : sourceBytes.Values.First();

            if (auxOnly && kind != "TypedefDecl") continue;

            if (compose && kind is not ("TypedefDecl" or "RecordDecl" or "EnumDecl")) continue;

            switch (kind)
            {
                case "EnumDecl" when name is not null:
                    api.Enums.Add(ExtractEnum(node, name, bytes) with { External = compose });
                    break;

                case "RecordDecl" when name is not null && node["completeDefinition"]?.GetValue<bool>() == true:
                    api.Structs.Add(ExtractStruct(node, name, bytes, errors) with { External = compose });
                    break;

                case "RecordDecl" when name is not null && !compose:
                    if (!api.Opaques.Contains(name)) api.Opaques.Add(name);
                    break;

                case "FunctionDecl" when name is not null && name.StartsWith(symbolPrefix, StringComparison.Ordinal) && HasSymbol(node):
                    api.Functions.Add(ExtractFunction(node, name, errors));
                    break;

                case "VarDecl" when name is not null && node["storageClass"]?.GetValue<string>() == "extern" && HasSymbol(node):
                    api.Variables.Add(new ApiVariable(name, node["type"]?.AsObject()["qualType"]?.GetValue<string>() ?? "",
                        DocParser.Parse(node).Summary is { Length: > 0 } doc ? doc : null));
                    break;

                case "VarDecl" when name is not null && !compose && node["storageClass"]?.GetValue<string>() == "static":
                    api.Statics.Add(name);
                    break;

                case "TypedefDecl" when name is not null:
                    {
                        var target = node["type"]?.AsObject()["qualType"]?.GetValue<string>() ?? "";
                        if (!target.StartsWith("struct ") && !target.StartsWith("union ") && !target.StartsWith("enum ") && target != name)
                            api.TypeAliases[name] = target;
                        if (ExtractCallback(node, name) is { } callback) api.Callbacks.Add(callback);
                        break;
                    }
            }
        }

        api.Opaques.RemoveAll(o => defined.Contains(o));
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
            string rawValue = next.ToString();
            var isInt = true;

            var initializer = Regex.Match(SliceRange(bytes, e), @"=\s*(.+?)\s*(?:,|\}|$)");
            var aliasOnly = initializer.Success
                && Regex.IsMatch(initializer.Groups[1].Value.Trim(), @"^[A-Za-z_]\w*$");

            if (aliasOnly)
            {
                isInt = false;
                rawValue = initializer.Groups[1].Value.Trim();
            }
            else
            {
                var folded = Folded(e);

                if (folded is not null && long.TryParse(folded, out var foldedValue))
                    rawValue = foldedValue.ToString();
                else if (initializer.Success && long.TryParse(initializer.Groups[1].Value.Trim(), out var literal))
                    rawValue = literal.ToString();
            }
            if (isInt) next = long.Parse(rawValue) + 1;
            values.Add(new ApiEnumValue(e["name"]!.GetValue<string>(), rawValue, isInt, doc.Length > 0 ? doc : null));
        }
        var parsed = DocParser.Parse(node);
        return new ApiEnum(name, parsed.Summary.Length > 0 ? parsed.Summary : null, values)
        {
            Tags = parsed.SummaryTags,
        };
    }

    /// <summary>
    /// The value clang folded an enum constant's initialiser to: a constant expression's, or the
    /// literal's when the initialiser is one literal under implicit casts.
    /// </summary>
    internal static string? Folded(JsonObject node)
    {
        foreach (var child in ((node["inner"] as JsonArray) ?? []).OfType<JsonObject>())
        {
            var kind = child["kind"]?.GetValue<string>();
            if (kind is "ConstantExpr" or "IntegerLiteral" && child["value"] is { } value) return value.GetValue<string>();
            if (kind is "ImplicitCastExpr" or "ParenExpr" && Folded(child) is { } inner) return inner;
        }
        return null;
    }

    static ApiStruct ExtractStruct(JsonObject node, string name, byte[] bytes, List<string> errors)
    {
        var fields = new List<ApiField>();
        var slots = new List<ApiSlot>();
        var order = new List<string>();
        ApiStruct? inline = null;
        var unnamed = 0;

        foreach (var c in (node["inner"] as JsonArray) ?? [])
        {
            var f = c!.AsObject();
            var memberKind = f["kind"]?.GetValue<string>();
            if (memberKind == "RecordDecl" && f["name"] is null)
            {
                inline = ExtractStruct(f, "", bytes, errors);
                continue;
            }
            if (memberKind != "FieldDecl") continue;
            var qual = f["type"]?.AsObject()["qualType"]?.GetValue<string>() ?? "";
            var declaredWith = qual.Contains("(anonymous") || qual.Contains("(unnamed") ? inline : null;
            var fieldName = f["name"]?.GetValue<string>() ?? $"unnamed_{unnamed++}";
            var (ret, paramTypes) = CTypes.FunctionPointer(qual);
            var (summaryTags, summary, pdocs, retTags, retDoc) = DocParser.Parse(f);
            order.Add(fieldName);

            if (ret is null)
            {
                var field = new ApiField(fieldName, declaredWith is null ? qual : "", summaryTags,
                    summary.Length > 0 ? summary : null);
                fields.Add(field with { Inline = declaredWith });
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
            for (var i = 1; i < paramTypes.Count; i++)
            {
                var pname = i < pnames.Count ? pnames[i] : null;
                var (tags, doc) = pname is not null && pdocs.TryGetValue(pname, out var d)
                    ? (d.Tags, d.Doc) : ([], "");
                slotParams.Add(new ApiParam(pname, paramTypes[i], tags, doc.Length > 0 ? doc : null));
            }
            slots.Add(new ApiSlot(fieldName, ret, summaryTags, summary.Length > 0 ? summary : null,
                retDoc.Length > 0 ? retDoc : null, slotParams)
            {
                ReturnTags = retTags,
                Receiver = paramTypes.Count > 0 ? paramTypes[0] : null,
            });
        }

        var (structTags, structDoc, _, _, _) = DocParser.Parse(node);
        var inDeclarationOrder = order.SequenceEqual(fields.Select(f => f.Name).Concat(slots.Select(s => s.Name)));
        return new ApiStruct(name, structDoc.Length > 0 ? structDoc : null, structTags, fields, slots)
        {
            IsUnion = node["tagUsed"]?.GetValue<string>() == "union",
            Order = inDeclarationOrder ? null : order,
        };
    }

    /// <summary>
    /// Describes a function-pointer typedef lane by lane, or returns
    /// <see langword="null"/> when the typedef names no prototype. A prototype carries
    /// its lanes' types in declaration order and none of their names — a name reaches
    /// the description only through the typedef's own <c>@param</c> documentation, which
    /// states the index it belongs to.
    /// </summary>
    static ApiCallback? ExtractCallback(JsonObject node, string name)
    {
        var proto = FindProto(node["inner"] as JsonArray);
        if (proto is null) return null;

        var (summaryTags, summary, pdocs, _, _) = DocParser.Parse(node);
        var laneNames = new Dictionary<int, string>();
        CollectParamIndices(node["inner"] as JsonArray, laneNames);

        var types = ((proto["inner"] as JsonArray) ?? [])
            .Select(t => t!["type"]?.AsObject()["qualType"]?.GetValue<string>() ?? "").ToList();
        if (types.Count == 0) return null;

        var lanes = types.Skip(1).Select((type, i) =>
        {
            var laneName = laneNames.TryGetValue(i, out var n) ? n : null;
            var (tags, doc) = laneName is not null && pdocs.TryGetValue(laneName, out var d)
                ? (d.Tags, d.Doc) : ([], "");
            return new ApiParam(laneName, type, tags, doc.Length > 0 ? doc : null);
        }).ToList();

        return new ApiCallback(name, types[0], summary.Length > 0 ? summary : null, lanes) { Tags = summaryTags };
    }

    static JsonObject? FindProto(JsonArray? inner)
    {
        foreach (var c in inner ?? [])
        {
            var n = c!.AsObject();
            var kind = n["kind"]?.GetValue<string>();
            if (kind == "FullComment") continue;
            if (kind == "FunctionProtoType") return n;
            if (FindProto(n["inner"] as JsonArray) is { } found) return found;
        }
        return null;
    }

    static void CollectParamIndices(JsonArray? inner, Dictionary<int, string> sink)
    {
        foreach (var c in inner ?? [])
        {
            var n = c!.AsObject();
            if (n["kind"]?.GetValue<string>() == "ParamCommandComment"
                && n["param"]?.GetValue<string>() is { } pname
                && n["paramIdx"]?.GetValue<int>() is { } idx)
                sink[idx] = pname;
            CollectParamIndices(n["inner"] as JsonArray, sink);
        }
    }

    /// <summary>
    /// Whether the declaration leaves a symbol a caller in another language could link
    /// against. A <c>static inline</c> helper in a header does not: every translation unit
    /// that includes it compiles its own copy and none of them is exported, so describing
    /// it as part of the API promises a binding that cannot be written.
    /// </summary>
    static bool HasSymbol(JsonObject node) => node["storageClass"]?.GetValue<string>() != "static";

    static ApiFunction ExtractFunction(JsonObject node, string name, List<string> errors)
    {
        var (_, summary, pdocs, retTags, retDoc) = DocParser.Parse(node);
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
            retDoc.Length > 0 ? retDoc : null, parameters)
        { ReturnTags = retTags };
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
}
