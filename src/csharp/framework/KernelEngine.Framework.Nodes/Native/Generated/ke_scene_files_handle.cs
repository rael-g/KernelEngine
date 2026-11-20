using System.Numerics;

using global::KernelEngine.Ecs;

using KernelEngine.Asset.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Framework.Native;
using KernelEngine.Io.Native;
using KernelEngine.Part.Native;
using KernelEngine.Result.Native;
using KernelEngine.Schedule.Native;
using KernelEngine.Scheduler.Native;
using KernelEngine.Settings.Native;

namespace KernelEngine.Framework.Nodes.Native;

public unsafe partial struct ke_scene_files_handle
{
    public ke_scene_files* @ref;

    [NativeTypeName("void (*)(ke_scene_files *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_files*, void> destroy;
}
