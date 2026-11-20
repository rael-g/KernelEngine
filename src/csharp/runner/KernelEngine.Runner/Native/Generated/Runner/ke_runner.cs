using System.Numerics;

using KernelEngine.Result.Native;

namespace KernelEngine.Runner.Native;

public unsafe partial struct ke_runner
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_runner *)")]
    public delegate* unmanaged[Cdecl]<ke_runner*, KernelEngine.Result.Native.Result> run;
}
