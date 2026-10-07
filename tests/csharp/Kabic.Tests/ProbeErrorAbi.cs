namespace Kabic.Tests;

internal static class ProbeErrorAbi
{
    static readonly string[] Singletons =
    [
        "KE_ERROR_GENERAL", "KE_ERROR_NOT_FOUND", "KE_ERROR_IO", "KE_ERROR_OUT_OF_MEMORY",
        "KE_ERROR_INVALID_ARGUMENT", "KE_ERROR_NOT_INITIALIZED", "KE_ERROR_NOT_SUPPORTED", "KE_ERROR_ALREADY_EXISTS",
    ];

    public static ApiModel Model()
    {
        var m = new ApiModel();
        m.Structs.Add(new ApiStruct("ke_error_type", null, [], [
            new ApiField("name", "const char *", [], null),
            new ApiField("parent", "const struct ke_error_type *", [], null)], []));
        m.Structs.Add(new ApiStruct("ke_error", null, [], [
            new ApiField("type", "const ke_error_type *", [], null),
            new ApiField("message", "const char *", [], null),
            new ApiField("file", "const char *", [], null),
            new ApiField("line", "uint32_t", [], null),
            new ApiField("cause", "const struct ke_error *", [], null)], []));
        m.Functions.Add(new ApiFunction("ke_error_is", "_Bool", null, null, [
            new ApiParam("err", "const ke_error *", [], null),
            new ApiParam("type", "const ke_error_type *", [], null)]));
        foreach (var name in Singletons) m.Variables.Add(new ApiVariable(name, "const ke_error_type", null));
        return m;
    }
}
