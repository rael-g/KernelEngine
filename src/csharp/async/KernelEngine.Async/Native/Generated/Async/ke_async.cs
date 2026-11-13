using System.Numerics;

using global::KernelEngine.Async;

using KernelEngine.Completion.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Async.Native;

public unsafe partial struct ke_async
{
    public void* handle;

    [NativeTypeName("ke_result (*)(ke_async *, const char *, ke_async_fn, void *, ke_completion *const *, uint32_t, ke_completion **)")]
    public delegate* unmanaged[Cdecl]<ke_async*, sbyte*, delegate* unmanaged[Cdecl]<void*, ke_async_ctx*, KernelEngine.Result.Native.Result>, void*, KernelEngine.Completion.Native.ke_completion**, uint, KernelEngine.Completion.Native.ke_completion**, KernelEngine.Result.Native.Result> submit;

    [NativeTypeName("ke_result (*)(ke_async *, ke_completion *)")]
    public delegate* unmanaged[Cdecl]<ke_async*, KernelEngine.Completion.Native.ke_completion*, KernelEngine.Result.Native.Result> cancel;

    [NativeTypeName("void (*)(ke_async *)")]
    public delegate* unmanaged[Cdecl]<ke_async*, void> drain;
}
