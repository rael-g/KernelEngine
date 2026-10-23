namespace Kabic.Tests;

internal static class ProbeResultAbi
{
    static readonly (string Name, int Value)[] Codes =
    [
        ("KE_OK", 0), ("KE_RESULT_GENERAL", 1), ("KE_RESULT_NOT_FOUND", 2), ("KE_RESULT_IO", 3),
        ("KE_RESULT_OUT_OF_MEMORY", 4), ("KE_RESULT_INVALID_ARGUMENT", 5), ("KE_RESULT_NOT_INITIALIZED", 6),
        ("KE_RESULT_NOT_SUPPORTED", 7), ("KE_RESULT_ALREADY_EXISTS", 8),
    ];

    public static ApiModel Model()
    {
        var m = new ApiModel();
        m.Enums.Add(new ApiEnum("ke_result", null,
            Codes.Select(c => new ApiEnumValue(c.Name, c.Value.ToString(), true, null)).ToList()));
        return m;
    }
}
