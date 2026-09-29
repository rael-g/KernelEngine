
using System.Text.Json.Nodes;

namespace Kabic.Frontend;

public static class Serialization
{
    public static JsonObject ToJson(this ApiModel m) => new()
    {
        ["enums"] = new JsonArray(m.Enums.Select(e => (JsonNode)e.ToJson()).ToArray()),
        ["structs"] = new JsonArray(m.Structs.Where(s => !s.IsVtable).Select(s => (JsonNode)s.ToJson()).ToArray()),
        ["vtables"] = new JsonArray(m.Structs.Where(s => s.IsVtable).Select(s => (JsonNode)s.ToJson()).ToArray()),
        ["functions"] = new JsonArray(m.Functions.Select(f => (JsonNode)f.ToJson()).ToArray()),
        ["callbacks"] = new JsonArray(m.Callbacks.Select(c => (JsonNode)c.ToJson()).ToArray()),
        ["type_aliases"] = m.TypeAliases.Aggregate(new JsonObject(),
            (o, kv) => { o[kv.Key] = kv.Value; return o; }),
    };

    public static JsonObject ToJson(this ApiParam p) => new()
    {
        ["name"] = p.Name,
        ["type"] = p.Type,
        ["tags"] = new JsonArray(p.Tags.Select(t => (JsonNode)t).ToArray()),
        ["doc"] = p.Doc,
    };

    public static JsonObject ToJson(this ApiEnumValue v) => new()
    {
        ["name"] = v.Name,
        ["value"] = v.IsInt ? JsonValue.Create(long.Parse(v.RawValue)) : JsonValue.Create(v.RawValue),
        ["doc"] = v.Doc,
    };

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

    public static JsonObject ToJson(this ApiField f) => new()
    {
        ["name"] = f.Name,
        ["type"] = f.Type,
        ["tags"] = new JsonArray(f.Tags.Select(t => (JsonNode)t).ToArray()),
        ["doc"] = f.Doc,
    };

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
        return o;
    }

    public static JsonObject ToJson(this ApiCallback c) => new()
    {
        ["name"] = c.Name,
        ["returns"] = c.Returns,
        ["doc"] = c.Doc,
        ["lanes"] = new JsonArray(c.Lanes.Select(l => (JsonNode)l.ToJson()).ToArray()),
    };

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
