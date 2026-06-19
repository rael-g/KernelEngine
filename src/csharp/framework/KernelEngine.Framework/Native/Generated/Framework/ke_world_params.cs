using KernelEngine.Common.Native;

namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_world_params
{
    [NativeTypeName("struct ke_task_scheduler *")]
    public KernelEngine.TaskScheduler.Native.ke_task_scheduler* task_scheduler;

    [NativeTypeName("ke_ecs *")]
    public KernelEngine.Ecs.Native.ke_ecs* ecs;

    [NativeTypeName("ke_runtime *")]
    public KernelEngine.Runtime.Native.ke_runtime* runtime;

    [NativeTypeName("struct ke_scene_tree *")]
    public ke_scene_tree* scene_tree;

    [NativeTypeName("const char *")]
    public sbyte* project_root;

    [NativeTypeName("struct ke_logger *")]
    public KernelEngine.Logger.Native.ke_logger* logger;
}
