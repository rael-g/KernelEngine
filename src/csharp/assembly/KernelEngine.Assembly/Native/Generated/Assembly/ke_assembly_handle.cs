using System.Numerics;

using global::KernelEngine.Assembly;
using global::KernelEngine.Logger;

using KernelEngine.Part.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Assembly.Native;

public unsafe partial struct ke_assembly_handle
{
    public ke_assembly* @ref;

    [NativeTypeName("void (*)(ke_assembly *)")]
    public delegate* unmanaged[Cdecl]<ke_assembly*, void> destroy;
}
