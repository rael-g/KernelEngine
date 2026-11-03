using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Logger;

using KernelEngine.Result.Native;

namespace KernelEngine.Configuration.Native;

[StructLayout(LayoutKind.Explicit)]
public unsafe partial struct ConfigValue
{
    [FieldOffset(0)]
    [NativeTypeName("int64_t")]
    public long I;

    [FieldOffset(0)]
    public double D;

    [FieldOffset(0)]
    public bool B;

    [FieldOffset(0)]
    [NativeTypeName("const char *")]
    public sbyte* S;
}
