using System.Runtime.InteropServices;

using KernelEngine.Logger.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Configuration.Native;

[StructLayout(LayoutKind.Explicit)]
public unsafe partial struct ke_config_value
{
    [FieldOffset(0)]
    [NativeTypeName("int64_t")]
    public long i;

    [FieldOffset(0)]
    public double d;

    [FieldOffset(0)]
    public bool b;

    [FieldOffset(0)]
    [NativeTypeName("const char *")]
    public sbyte* s;
}
