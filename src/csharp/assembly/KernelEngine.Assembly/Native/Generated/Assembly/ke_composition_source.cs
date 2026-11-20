using System.Numerics;

using global::KernelEngine.Assembly;
using global::KernelEngine.Logger;

using KernelEngine.Part.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Assembly.Native;

public unsafe partial struct ke_composition_source
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_composition_source *, ke_assembly *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_composition_source*, ke_assembly*, sbyte*, KernelEngine.Result.Native.Result> load;
}
