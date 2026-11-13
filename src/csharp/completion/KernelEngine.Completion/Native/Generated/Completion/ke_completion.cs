using System.Numerics;

using KernelEngine.Result.Native;

namespace KernelEngine.Completion.Native;

public unsafe partial struct ke_completion
{
    public void* handle;

    [NativeTypeName("bool (*)(ke_completion *, ke_result *)")]
    public delegate* unmanaged[Cdecl]<ke_completion*, KernelEngine.Result.Native.Result*, bool> poll;

    [NativeTypeName("ke_result (*)(ke_completion *)")]
    public delegate* unmanaged[Cdecl]<ke_completion*, KernelEngine.Result.Native.Result> wait;

    [NativeTypeName("void (*)(ke_completion *)")]
    public delegate* unmanaged[Cdecl]<ke_completion*, void> release;
}
