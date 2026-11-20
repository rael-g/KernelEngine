using System.Numerics;

using global::KernelEngine.Assembly;
using global::KernelEngine.Logger;

using KernelEngine.Part.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Assembly.Native;

public unsafe partial struct ke_composition_source_handle
{
    public ke_composition_source* @ref;

    [NativeTypeName("void (*)(ke_composition_source *)")]
    public delegate* unmanaged[Cdecl]<ke_composition_source*, void> destroy;
}
