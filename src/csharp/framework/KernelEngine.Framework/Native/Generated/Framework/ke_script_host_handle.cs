using KernelEngine.Asset.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Input.Native;
using KernelEngine.Io.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_script_host_handle
{
    public ke_script_host* @ref;

    [NativeTypeName("void (*)(ke_script_host *)")]
    public delegate* unmanaged[Cdecl]<ke_script_host*, void> destroy;
}
