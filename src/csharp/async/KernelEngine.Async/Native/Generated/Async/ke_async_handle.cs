using System.Numerics;

using KernelEngine.Completion.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Async.Native;

public unsafe partial struct ke_async_handle
{
    public ke_async* @ref;

    [NativeTypeName("void (*)(ke_async *)")]
    public delegate* unmanaged[Cdecl]<ke_async*, void> destroy;
}
