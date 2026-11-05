using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Input;
using global::KernelEngine.Logger;

using KernelEngine.Asset.Native;
using KernelEngine.Configuration.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Io.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_component_registry_handle
{
    public ke_component_registry* @ref;

    [NativeTypeName("void (*)(ke_component_registry *)")]
    public delegate* unmanaged[Cdecl]<ke_component_registry*, void> destroy;
}
