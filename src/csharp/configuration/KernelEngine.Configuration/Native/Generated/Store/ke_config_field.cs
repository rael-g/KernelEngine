using KernelEngine.Logger.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Configuration.Native;

public unsafe partial struct ke_config_field
{
    [NativeTypeName("const char *")]
    public sbyte* key;

    public ke_config_type type;

    [NativeTypeName("uint32_t")]
    public uint offset;

    [NativeTypeName("uint32_t")]
    public uint size;

    public ke_config_value default_value;
}
