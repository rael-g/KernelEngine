using System.Numerics;

using KernelEngine.Completion.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Async.Native;

public unsafe partial struct ke_async_ctx
{
    public void* handle;

    [NativeTypeName("const ke_result *")]
    public KernelEngine.Result.Native.Result* dep_results;

    [NativeTypeName("uint32_t")]
    public uint dep_count;

    [NativeTypeName("bool (*)(ke_async_ctx *)")]
    public delegate* unmanaged[Cdecl]<ke_async_ctx*, bool> cancelled;
}
