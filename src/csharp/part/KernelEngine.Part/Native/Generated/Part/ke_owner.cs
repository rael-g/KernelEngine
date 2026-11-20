using System.Numerics;

using global::KernelEngine.Logger;
using global::KernelEngine.Part;

using KernelEngine.Completion.Native;
using KernelEngine.Result.Native;
using KernelEngine.Settings.Native;

namespace KernelEngine.Part.Native;

public unsafe partial struct ke_owner
{
    public void* @ref;

    [NativeTypeName("void (*)(void *)")]
    public delegate* unmanaged[Cdecl]<void*, void> destroy;
}
