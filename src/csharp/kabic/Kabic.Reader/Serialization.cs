
using System.Text.Json.Nodes;

namespace Kabic.Reader;

/// <summary>
/// Writes the declarations of an <c>ApiModel</c> and of its parts as JSON objects under fixed key
/// names.
/// </summary>
public static class Serialization
{
    /// <summary>
    /// Writes the model as one JSON object, with the enum, struct, vtable, function and callback
    /// arrays and the type aliases, adding the opaque records, the statics, the constants and the variables when there are any.
    /// </summary>
    public static JsonObject ToJson(this ApiModel m)
    {
        var json = new JsonObject
        {
            ["enums"] = new JsonArray(m.Enums.Select(e => (JsonNode)e.ToJson()).ToArray()),
            ["structs"] = new JsonArray(m.Structs.Where(s => !s.IsVtable).Select(s => (JsonNode)s.ToJson()).ToArray()),
            ["vtables"] = new JsonArray(m.Structs.Where(s => s.IsVtable).Select(s => (JsonNode)s.ToJson()).ToArray()),
            ["functions"] = new JsonArray(m.Functions.Select(f => (JsonNode)f.ToJson()).ToArray()),
            ["callbacks"] = new JsonArray(m.Callbacks.Select(c => (JsonNode)c.ToJson()).ToArray()),
            ["type_aliases"] = m.TypeAliases.Aggregate(new JsonObject(),
            (o, kv) => { o[kv.Key] = kv.Value; return o; }),
        };
        if (m.Opaques.Count > 0)
            json["opaques"] = new JsonArray(m.Opaques.Select(o => (JsonNode)o).ToArray());
        if (m.Statics.Count > 0)
            json["statics"] = new JsonArray(m.Statics.Select(n => (JsonNode)n).ToArray());
        if (m.Constants.Count > 0)
            json["constants"] = new JsonArray(m.Constants.Select(c =>
            {
                var o = new JsonObject { ["name"] = c.Name, ["type"] = c.Type };
                if (c.Value is not null) o["value"] = c.Value;
                if (c.Fields is not null)
                    o["fields"] = new JsonArray(c.Fields.Select(f => (JsonNode)new JsonObject { ["name"] = f.Name, ["value"] = f.Value }).ToArray());
                if (c.Doc is not null) o["doc"] = c.Doc;
                return (JsonNode)o;
            }).ToArray());
        if (m.Variables.Count > 0)
            json["variables"] = new JsonArray(m.Variables.Select(v => (JsonNode)new JsonObject
            {
                ["name"] = v.Name,
                ["type"] = v.Type,
                ["doc"] = v.Doc,
            }).ToArray());
        return json;
    }

    /// <summary>
    /// Writes a parameter as an object with its name, type, tags and documentation.
    /// </summary>
    public static JsonObject ToJson(this ApiParam p) => new()
    {
        ["name"] = p.Name,
        ["type"] = p.Type,
        ["tags"] = new JsonArray(p.Tags.Select(t => (JsonNode)t).ToArray()),
        ["doc"] = p.Doc,
    };

    /// <summary>
    /// Writes an enumerator as an object with its name, its value and its documentation. The value
    /// is a number when the enumerator is an integer and text otherwise.
    /// </summary>
    public static JsonObject ToJson(this ApiEnumValue v) => new()
    {
        ["name"] = v.Name,
        ["value"] = v.IsInt ? JsonValue.Create(long.Parse(v.RawValue)) : JsonValue.Create(v.RawValue),
        ["doc"] = v.Doc,
    };

    /// <summary>
    /// Writes an enum as an object with its name, documentation and values, adding external and
    /// tags when they are set.
    /// </summary>
    public static JsonObject ToJson(this ApiEnum e)
    {
        var o = new JsonObject
        {
            ["name"] = e.Name,
            ["doc"] = e.Doc,
            ["values"] = new JsonArray(e.Values.Select(v => (JsonNode)v.ToJson()).ToArray()),
        };
        if (e.External) o["external"] = true;
        if (e.Tags.Count > 0) o["tags"] = new JsonArray(e.Tags.Select(t => (JsonNode)t!).ToArray());
        return o;
    }

    /// <summary>
    /// Writes a struct field as an object with its name, type, tags and documentation, adding the
    /// record it is declared with when it has one.
    /// </summary>
    public static JsonObject ToJson(this ApiField f)
    {
        var o = new JsonObject
        {
            ["name"] = f.Name,
            ["type"] = f.Type,
            ["tags"] = new JsonArray(f.Tags.Select(t => (JsonNode)t).ToArray()),
            ["doc"] = f.Doc,
        };
        if (f.Inline is not null) o["inline"] = f.Inline.ToJson();
        return o;
    }

    /// <summary>
    /// Writes a vtable slot as an object with its name, return type, tags, documentation, return
    /// documentation and parameters, adding return tags and receiver when they are present.
    /// </summary>
    public static JsonObject ToJson(this ApiSlot s)
    {
        var o = new JsonObject
        {
            ["name"] = s.Name,
            ["returns"] = s.Returns,
            ["tags"] = new JsonArray(s.Tags.Select(t => (JsonNode)t).ToArray()),
            ["doc"] = s.Doc,
            ["return_doc"] = s.ReturnDoc,
            ["params"] = new JsonArray(s.Params.Select(p => (JsonNode)p.ToJson()).ToArray()),
        };
        if (s.ReturnTags.Count > 0)
            o["return_tags"] = new JsonArray(s.ReturnTags.Select(t => (JsonNode)t).ToArray());
        if (s.Receiver is not null) o["receiver"] = s.Receiver;
        return o;
    }

    /// <summary>
    /// Writes a struct as an object with its name, documentation, tags and fields, adding slots,
    /// external, union and declaration order when they are present.
    /// </summary>
    public static JsonObject ToJson(this ApiStruct s)
    {
        var o = new JsonObject
        {
            ["name"] = s.Name,
            ["doc"] = s.Doc,
            ["tags"] = new JsonArray(s.Tags.Select(t => (JsonNode)t).ToArray()),
            ["fields"] = new JsonArray(s.Fields.Select(f => (JsonNode)f.ToJson()).ToArray()),
        };
        if (s.Slots.Count > 0)
            o["slots"] = new JsonArray(s.Slots.Select(slot => (JsonNode)slot.ToJson()).ToArray());
        if (s.External) o["external"] = true;
        if (s.IsUnion) o["union"] = true;
        if (s.Order is not null) o["order"] = new JsonArray(s.Order.Select(n => (JsonNode)n).ToArray());
        return o;
    }

    /// <summary>
    /// Writes a callback as an object with its name, return type, documentation and lanes, adding
    /// its tags when it has any.
    /// </summary>
    public static JsonObject ToJson(this ApiCallback c)
    {
        var o = new JsonObject
        {
            ["name"] = c.Name,
            ["returns"] = c.Returns,
            ["doc"] = c.Doc,
            ["lanes"] = new JsonArray(c.Lanes.Select(l => (JsonNode)l.ToJson()).ToArray()),
        };
        if (c.Tags.Count > 0) o["tags"] = new JsonArray(c.Tags.Select(t => (JsonNode)t).ToArray());
        return o;
    }

    /// <summary>
    /// Writes a function as an object with its name, return type, documentation, return
    /// documentation and parameters, adding return tags when they are present.
    /// </summary>
    public static JsonObject ToJson(this ApiFunction f)
    {
        var o = new JsonObject
        {
            ["name"] = f.Name,
            ["returns"] = f.Returns,
            ["doc"] = f.Doc,
            ["return_doc"] = f.ReturnDoc,
            ["params"] = new JsonArray(f.Params.Select(p => (JsonNode)p.ToJson()).ToArray()),
        };
        if (f.ReturnTags.Count > 0)
            o["return_tags"] = new JsonArray(f.ReturnTags.Select(t => (JsonNode)t).ToArray());
        return o;
    }
}
