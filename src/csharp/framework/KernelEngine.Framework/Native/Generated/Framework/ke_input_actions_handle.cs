using KernelEngine.Asset.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Input.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_input_actions_handle
{
    public ke_input_actions* @ref;

    [NativeTypeName("void (*)(ke_input_actions *)")]
    public delegate* unmanaged[Cdecl]<ke_input_actions*, void> destroy;
}
