using System.Numerics;

using global::KernelEngine.Logger;

using KernelEngine.Result.Native;

namespace KernelEngine.Configuration.Native;

public unsafe partial struct ConfigField
{
    [NativeTypeName("const char *")]
    public sbyte* Key;

    [NativeTypeName("ke_config_type")]
    public ConfigType Type;

    [NativeTypeName("uint32_t")]
    public uint Offset;

    [NativeTypeName("uint32_t")]
    public uint Size;

    [NativeTypeName("const char *const *")]
    public sbyte** EnumNames;
}
