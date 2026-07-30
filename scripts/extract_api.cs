#!/usr/bin/env dotnet run

// Extracts a semantic description (ke_api.json) of one or more public headers:
// enums, plain structs, vtable structs (structs holding function-pointer
// fields), and free functions, together with each slot's doc comment and the
// bracketed [tag] semantics riding inside it — see docs/ScriptingArchitectureV3.md
// §5 for the annotation vocabulary and why it lives in doc comments rather than
// __attribute__((annotate(...))) (attributes are silently dropped by clang on
// function-pointer-field and function-typedef parameters — every public slot
// in this codebase is exactly that shape).
//
// ke_api.json is a build artifact: regenerate it from headers, never hand-edit
// it, same rule that already governs src/csharp/*/Native/Generated/.
//
// Usage: dotnet run scripts/extract_api.cs -- --out <path> [-I <dir>]... <header.h>...

using System.Diagnostics;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

static string ScriptDir([CallerFilePath] string path = "") => Path.GetDirectoryName(path)!;
var rootDir = Path.GetFullPath(Path.Combine(ScriptDir(), ".."));

string? outPath = null;
string? zigOverride = null;
var includeDirs = new List<string>();
var headers = new List<string>();

for (var i = 0; i < args.Length; i++)
{
    switch (args[i])
    {
        case "--out": outPath = args[++i]; break;
        case "--zig": zigOverride = args[++i]; break;
        case "-I": includeDirs.Add(args[++i]); break;
        default: headers.Add(args[i]); break;
    }
}

if (outPath is null || headers.Count == 0)
{
    Console.Error.WriteLine("usage: dotnet run scripts/extract_api.cs -- --out <path> [-I <dir>]... <header.h>...");
    return 1;
}

var zig = ResolveZig(zigOverride);
var headerPaths = headers.Select(Path.GetFullPath).ToList();
var headerNames = headerPaths.Select(Path.GetFileName).Where(n => n is not null).Select(n => n!).ToHashSet();

// -- run clang's AST dumper via `zig cc` (zig IS clang; no extra toolchain) --

var tuDir = Path.Combine(Path.GetTempPath(), "ke_extract_api_" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(tuDir);
var tuPath = Path.Combine(tuDir, "tu.c");
File.WriteAllLines(tuPath, headerPaths.Select(h => $"#include \"{h.Replace('\\', '/')}\""));

string astJson;
try
{
    astJson = RunAstDump(zig, tuPath, includeDirs);
}
finally
{
    Directory.Delete(tuDir, recursive: true);
}

var ast = JsonNode.Parse(astJson)!.AsObject();

// Raw bytes (not decoded text) of every header, because clang reports byte
// offsets and this codebase has non-ASCII box-drawing characters in comments;
// slicing a decoded string silently shifts every offset after the first one.
var sourceBytes = headerPaths.ToDictionary(p => p, File.ReadAllBytes);

var api = Extractor.Extract(ast, headerNames, sourceBytes);

if (api.Errors.Count > 0)
{
    foreach (var e in api.Errors) Console.Error.WriteLine($"ERROR: {e}");
    return 1;
}

Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(outPath))!);
// Built as a JsonNode tree, not JsonSerializer.Serialize<T>: file-based `dotnet run`
// apps disable reflection-based serialization by default in .NET 10, and a manual
// tree needs no source-generated JsonSerializerContext to sidestep that.
File.WriteAllText(outPath, api.ToJson().ToJsonString(new JsonSerializerOptions { WriteIndented = true }));

Console.WriteLine($"wrote {outPath}: enums={api.Enums.Count} structs={api.Structs.Count} "
    + $"vtables={api.Vtables.Count} functions={api.Functions.Count}");
return 0;

// ---------------------------------------------------------------------------

static string ResolveZig(string? overridePath)
{
    if (overridePath is not null) return overridePath;
    var fromPath = FindOnPath("zig");
    if (fromPath is not null) return fromPath;
    // Matches this project's distrobox dev-container convention (see
    // .distrobox/dev/.bashrc); a build-time-required override still exists via --zig.
    var distrobox = Path.Combine(Environment.GetEnvironmentVariable("HOME") ?? "",
        "zig-x86_64-linux-0.16.0", "zig");
    if (File.Exists(distrobox)) return distrobox;
    throw new InvalidOperationException("zig not found on PATH; pass --zig <path>");
}

static string? FindOnPath(string exe)
{
    var path = Environment.GetEnvironmentVariable("PATH") ?? "";
    foreach (var dir in path.Split(Path.PathSeparator))
    {
        var candidate = Path.Combine(dir, exe);
        if (File.Exists(candidate)) return candidate;
    }
    return null;
}

// `zig cc -Xclang -ast-dump=json -fsyntax-only` reliably emits a complete,
// valid AST on stdout but still exits 1 with a spurious `<tu>:1:1: error:
// FileNotFound` on stderr for the top-level translation unit — a zig-driver
// quirk (observed on zig 0.16.0), not a real failure. Genuine header errors
// (missing include, syntax error) show up as additional, differently-worded
// diagnostics alongside it, so validity is judged by whether stdout parses as
// non-trivial JSON, not by the process exit code.
static string RunAstDump(string zig, string tuPath, List<string> includeDirs)
{
    using var process = new Process
    {
        StartInfo = new ProcessStartInfo(zig)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        },
    };
    foreach (var a in new[] { "cc", "-Xclang", "-ast-dump=json", "-fsyntax-only", "-fparse-all-comments", tuPath })
        process.StartInfo.ArgumentList.Add(a);
    foreach (var d in includeDirs) { process.StartInfo.ArgumentList.Add("-I"); process.StartInfo.ArgumentList.Add(d); }
    process.Start();
    var stdout = process.StandardOutput.ReadToEnd();
    var stderr = process.StandardError.ReadToEnd();
    process.WaitForExit();

    if (stdout.Length < 2 || stdout[0] != '{')
        throw new InvalidOperationException($"zig cc produced no AST:\n{stderr}");

    var realErrors = stderr.Split('\n')
        .Where(l => l.Contains("error:") && !l.Contains($"{Path.GetFileName(tuPath)}:1:1: error: FileNotFound"))
        .ToList();
    if (realErrors.Count > 0)
        throw new InvalidOperationException("header failed to parse:\n" + string.Join('\n', realErrors));

    return stdout;
}

// -- output model -------------------------------------------------------------
//
// Each type builds its own JsonObject (ToJson) instead of going through
// JsonSerializer.Serialize<T>: file-based `dotnet run` apps disable
// reflection-based serialization by default in .NET 10, and hand-built trees
// need no source-generated JsonSerializerContext to route around that.

record ApiParam(string? Name, string Type, IReadOnlyList<string> Tags, string? Doc)
{
    public JsonObject ToJson() => new()
    {
        ["name"] = Name,
        ["type"] = Type,
        ["tags"] = new JsonArray(Tags.Select(t => (JsonNode)t).ToArray()),
        ["doc"] = Doc,
    };
}

record ApiEnumValue(string Name, object Value, string? Doc)
{
    public JsonObject ToJson() => new()
    {
        ["name"] = Name,
        ["value"] = Value switch { long l => JsonValue.Create(l), _ => JsonValue.Create((string)Value) },
        ["doc"] = Doc,
    };
}

record ApiEnum(string Name, string? Doc, IReadOnlyList<ApiEnumValue> Values)
{
    public JsonObject ToJson() => new()
    {
        ["name"] = Name,
        ["doc"] = Doc,
        ["values"] = new JsonArray(Values.Select(v => (JsonNode)v.ToJson()).ToArray()),
    };
}

record ApiField(string Name, string Type, string? Doc)
{
    public JsonObject ToJson() => new() { ["name"] = Name, ["type"] = Type, ["doc"] = Doc };
}

record ApiSlot(string Name, string Returns, string? Doc, string? ReturnDoc, IReadOnlyList<ApiParam> Params)
{
    public JsonObject ToJson() => new()
    {
        ["name"] = Name,
        ["returns"] = Returns,
        ["doc"] = Doc,
        ["return_doc"] = ReturnDoc,
        ["params"] = new JsonArray(Params.Select(p => (JsonNode)p.ToJson()).ToArray()),
    };
}

record ApiStruct(string Name, string? Doc, IReadOnlyList<ApiField> Fields, IReadOnlyList<ApiSlot>? Slots)
{
    public JsonObject ToJson()
    {
        var o = new JsonObject
        {
            ["name"] = Name,
            ["doc"] = Doc,
            ["fields"] = new JsonArray(Fields.Select(f => (JsonNode)f.ToJson()).ToArray()),
        };
        if (Slots is { Count: > 0 })
            o["slots"] = new JsonArray(Slots.Select(s => (JsonNode)s.ToJson()).ToArray());
        return o;
    }
}

record ApiFunction(string Name, string Returns, string? Doc, string? ReturnDoc, IReadOnlyList<ApiParam> Params)
{
    public JsonObject ToJson() => new()
    {
        ["name"] = Name,
        ["returns"] = Returns,
        ["doc"] = Doc,
        ["return_doc"] = ReturnDoc,
        ["params"] = new JsonArray(Params.Select(p => (JsonNode)p.ToJson()).ToArray()),
    };
}

class ApiModel
{
    public List<ApiEnum> Enums { get; } = [];
    public List<ApiStruct> Structs { get; } = [];
    public List<ApiStruct> Vtables { get; } = [];
    public List<ApiFunction> Functions { get; } = [];
    public List<string> Errors { get; } = [];

    public JsonObject ToJson() => new()
    {
        ["enums"] = new JsonArray(Enums.Select(e => (JsonNode)e.ToJson()).ToArray()),
        ["structs"] = new JsonArray(Structs.Select(s => (JsonNode)s.ToJson()).ToArray()),
        ["vtables"] = new JsonArray(Vtables.Select(v => (JsonNode)v.ToJson()).ToArray()),
        ["functions"] = new JsonArray(Functions.Select(f => (JsonNode)f.ToJson()).ToArray()),
    };
}

// -- doc-comment parsing: clang's Doxygen-lite comment AST -------------------
//
// @param tags carry a leading `[tag1,tag2]` block, which is this codebase's
// only annotation vocabulary (docs/ScriptingArchitectureV3.md §5.2) — nothing
// downstream should ever need __attribute__((annotate(...))) again.

static class DocParser
{
    static readonly Regex TagBlock = new(@"^\s*\[([^\]]+)\]\s*");

    public static (string Summary, Dictionary<string, (List<string> Tags, string Doc)> Params, string ReturnDoc)
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
        return (string.Join(' ', string.Join(' ', summary).Split(' ', StringSplitOptions.RemoveEmptyEntries)),
                pmap, string.Join(' ', string.Join(' ', returnChunks).Split(' ', StringSplitOptions.RemoveEmptyEntries)));
    }

    public static (string Summary, string Doc) SplitTagsSingle(string raw)
    {
        var m = TagBlock.Match(raw);
        var tags = m.Success ? m.Groups[1].Value : "";
        var rest = m.Success ? TagBlock.Replace(raw, "", 1) : raw;
        return (tags, rest.Trim());
    }
}

// -- declaration-text slicing: recovering what the AST alone cannot ----------
//
// Parameter names are absent from the AST for function-pointer fields and
// function typedefs: C function *types* carry no parameter names. Clang does
// report the exact byte range of most declarations, but that range collapses
// to empty when the declaration's type comes through a macro (`bool` from
// <stdbool.h> is the case that bit this extractor during development) — so
// names are recovered by finding the `(*name)(...)` declarator text directly,
// which does not depend on those ranges at all.

static class DeclText
{
    public static List<string?> FnPtrParamNames(byte[] sourceBytes, string fieldName)
    {
        var text = System.Text.Encoding.UTF8.GetString(sourceBytes);
        var m = Regex.Match(text, @"\(\s*\*\s*" + Regex.Escape(fieldName) + @"\s*\)\s*\(");
        if (!m.Success) return [];
        return ParamsFrom(text, m.Index + m.Length - 1);
    }

    public static List<string?> FreeFnParamNames(JsonObject fn)
    {
        // Function (not function-pointer) declarations DO carry ParmVarDecl
        // children with real names — no source slicing needed.
        return (fn["inner"] as JsonArray)?
            .Where(c => c?["kind"]?.GetValue<string>() == "ParmVarDecl")
            .Select(c => c!["name"]?.GetValue<string>())
            .ToList() ?? [];
    }

    /// Splits a balanced-parens argument list starting right after `(` at `openParen`,
    /// pulling the trailing identifier off each comma-separated parameter.
    static List<string?> ParamsFrom(string text, int openParen)
    {
        var depth = 0;
        var start = -1;
        for (var i = openParen; i < text.Length; i++)
        {
            if (text[i] == '(') { depth++; if (start < 0) start = i + 1; }
            else if (text[i] == ')') { depth--; if (depth == 0) return SplitParams(text[start..i]); }
        }
        return [];
    }

    static readonly Regex TrailingIdent = new(@"([A-Za-z_]\w*)\s*(\[\s*\w*\s*\])?\s*$");

    static List<string?> SplitParams(string inner)
    {
        var result = new List<string?>();
        var depth = 0;
        var cur = "";
        foreach (var ch in inner + ",")
        {
            if (ch == ',' && depth == 0)
            {
                var m = TrailingIdent.Match(cur.Trim());
                result.Add(m.Success ? m.Groups[1].Value : null);
                cur = "";
            }
            else
            {
                if (ch is '(' or '[') depth++;
                if (ch is ')' or ']') depth--;
                cur += ch;
            }
        }
        return result;
    }
}

// -- the extractor proper -----------------------------------------------------

static class Extractor
{
    public static ApiModel Extract(JsonObject ast, HashSet<string> headerNames, Dictionary<string, byte[]> sourceBytes)
    {
        var api = new ApiModel();
        string? currentFile = null;

        // clang's JSON AST is delta-encoded: loc.file (NOT includedFrom.file,
        // which names the *including* file and would misattribute every
        // declaration to the synthesized translation unit) appears only when
        // it changes from the previous node, so the current file has to be
        // carried forward across siblings.
        (bool Owned, string? File) Owns(JsonObject node)
        {
            var f = node["loc"]?.AsObject()["file"]?.GetValue<string>();
            if (f is not null) currentFile = f;
            return (currentFile is not null && headerNames.Contains(Path.GetFileName(currentFile)), currentFile);
        }

        var top = ast["inner"]!.AsArray();
        foreach (var nodeRaw in top)
        {
            var node = nodeRaw!.AsObject();
            var (owned, file) = Owns(node);
            if (!owned) continue;

            var kind = node["kind"]?.GetValue<string>();
            var name = node["name"]?.GetValue<string>();
            var bytes = file is not null && sourceBytes.TryGetValue(file, out var b) ? b : sourceBytes.Values.First();

            switch (kind)
            {
                case "EnumDecl" when name is not null:
                    api.Enums.Add(ExtractEnum(node, name, bytes));
                    break;

                case "RecordDecl" when name is not null && node["completeDefinition"]?.GetValue<bool>() == true:
                    var rec = ExtractStruct(node, name, bytes, api.Errors);
                    (rec.Slots is { Count: > 0 } ? api.Vtables : api.Structs).Add(rec);
                    break;

                case "FunctionDecl" when name is not null && name.StartsWith("ke_"):
                    api.Functions.Add(ExtractFunction(node, name, api.Errors));
                    break;
            }
        }

        return api;
    }

    static ApiEnum ExtractEnum(JsonObject node, string name, byte[] bytes)
    {
        var values = new List<ApiEnumValue>();
        object next = 0L;
        foreach (var c in (node["inner"] as JsonArray) ?? [])
        {
            var e = c!.AsObject();
            if (e["kind"]?.GetValue<string>() != "EnumConstantDecl") continue;
            var doc = DocParser.Parse(e).Summary;
            var literalText = SliceRange(bytes, e);
            var m = Regex.Match(literalText, @"=\s*(-?\w+)");
            object value = next;
            if (m.Success)
            {
                var tok = m.Groups[1].Value;
                value = Regex.IsMatch(tok, @"^-?\d+$") ? long.Parse(tok) : tok;
            }
            if (value is long l) next = l + 1;
            values.Add(new ApiEnumValue(e["name"]!.GetValue<string>(), value, doc.Length > 0 ? doc : null));
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
            var fieldName = f["name"]!.GetValue<string>();
            var qual = f["type"]?.AsObject()["qualType"]?.GetValue<string>() ?? "";
            var (ret, paramTypes) = SplitFnPtr(qual);
            var (summary, pdocs, retDoc) = DocParser.Parse(f);

            if (ret is null)
            {
                fields.Add(new ApiField(fieldName, qual, summary.Length > 0 ? summary : null));
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
            slots.Add(new ApiSlot(fieldName, ret, summary.Length > 0 ? summary : null,
                retDoc.Length > 0 ? retDoc : null, slotParams));
        }

        var structDoc = DocParser.Parse(node).Summary;
        return new ApiStruct(name, structDoc.Length > 0 ? structDoc : null, fields, slots.Count > 0 ? slots : null);
    }

    static ApiFunction ExtractFunction(JsonObject node, string name, List<string> errors)
    {
        var (summary, pdocs, retDoc) = DocParser.Parse(node);
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
