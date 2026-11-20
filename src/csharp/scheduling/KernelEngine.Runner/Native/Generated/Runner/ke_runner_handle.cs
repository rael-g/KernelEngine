using System.Numerics;

using KernelEngine.Result.Native;

namespace KernelEngine.Runner.Native;

public unsafe partial struct ke_runner_handle
{
    public ke_runner* @ref;

    [NativeTypeName("void (*)(ke_runner *)")]
    public delegate* unmanaged[Cdecl]<ke_runner*, void> destroy;
}
