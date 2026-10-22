using KernelEngine.Common.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.View.Native;

public unsafe partial struct ke_view_space_handle
{
    public ke_view_space* @ref;

    [NativeTypeName("void (*)(ke_view_space *)")]
    public delegate* unmanaged[Cdecl]<ke_view_space*, void> destroy;
}
