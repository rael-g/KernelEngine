using System.Numerics;

using global::KernelEngine.Common;
using global::KernelEngine.Ecs;
using global::KernelEngine.Physics;
using global::KernelEngine.Render;

using KernelEngine.Asset.Native;
using KernelEngine.Audio.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Framework.Native;
using KernelEngine.Io.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;

namespace KernelEngine.Framework.Nodes.Native;

public unsafe partial struct ke_scene_files
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_scene_files *, const char *, ke_entity, ke_ecs_commands *, ke_entity *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_files*, sbyte*, global::KernelEngine.Ecs.Entity, KernelEngine.Ecs.Native.ke_ecs_commands*, global::KernelEngine.Ecs.Entity*, KernelEngine.Result.Native.Result> instantiate;

    [NativeTypeName("ke_result (*)(struct ke_scene_files *, ke_ecs_commands *, const char *, ke_entity *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_files*, KernelEngine.Ecs.Native.ke_ecs_commands*, sbyte*, global::KernelEngine.Ecs.Entity*, KernelEngine.Result.Native.Result> open;
}
