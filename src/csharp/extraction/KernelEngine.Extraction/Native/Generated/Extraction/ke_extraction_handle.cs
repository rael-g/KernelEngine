using System.Numerics;

using global::KernelEngine.Ecs;

using KernelEngine.Completion.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Extraction.Native;

public unsafe partial struct ke_extraction_handle
{
    public ke_extraction* @ref;

    [NativeTypeName("void (*)(ke_extraction *)")]
    public delegate* unmanaged[Cdecl]<ke_extraction*, void> destroy;
}
