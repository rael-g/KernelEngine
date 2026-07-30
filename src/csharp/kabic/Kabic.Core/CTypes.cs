namespace Kabic;

/// Operations on a raw C type string (`"const ke_log_event *"`) that have
/// nothing to do with any target language's naming or type-mapping
/// conventions — every backend needs to know whether a type is a pointer and
/// what it points to, none of them decide it differently.
public static class CTypes
{
    public static bool IsPointer(string cType) => cType.TrimEnd().EndsWith('*');

    public static string Deref(string cType) =>
        cType.Trim().Replace("const ", "").Replace("struct ", "").TrimEnd('*', ' ');
}
