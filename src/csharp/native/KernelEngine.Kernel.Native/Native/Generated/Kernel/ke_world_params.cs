namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_world_params
{
    [NativeTypeName("struct ke_task_scheduler *")]
    public ke_task_scheduler* task_scheduler;

    public ke_ecs* ecs;

    public ke_runtime* runtime;

    [NativeTypeName("struct ke_scene_tree *")]
    public ke_scene_tree* scene_tree;

    [NativeTypeName("const char *")]
    public sbyte* project_root;

    [NativeTypeName("struct ke_logger *")]
    public ke_logger* logger;
}
