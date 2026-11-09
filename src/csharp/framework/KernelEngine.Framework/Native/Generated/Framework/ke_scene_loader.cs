using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Input;
using global::KernelEngine.Logger;

using KernelEngine.Asset.Native;
using KernelEngine.Configuration.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Input.Native;
using KernelEngine.Io.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_scene_loader
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_scene_loader *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_loader*, sbyte*, KernelEngine.Result.Native.Result> load;

    [NativeTypeName("ke_result (*)(struct ke_scene_loader *, const char *, ke_entity, ke_ecs_commands *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_loader*, sbyte*, global::KernelEngine.Ecs.Entity, KernelEngine.Ecs.Native.ke_ecs_commands*, KernelEngine.Result.Native.Result> instantiate;

    [NativeTypeName("ke_result (*)(struct ke_scene_loader *, ke_script_factory_func, void *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_loader*, delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Ecs.Entity, sbyte*, KernelEngine.Result.Native.Result>, void*, KernelEngine.Result.Native.Result> register_script_factory;
}
