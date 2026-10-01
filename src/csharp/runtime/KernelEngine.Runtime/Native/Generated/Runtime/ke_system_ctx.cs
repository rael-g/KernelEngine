using KernelEngine.Common.Native;

namespace KernelEngine.Runtime.Native;

public unsafe partial struct ke_system_ctx
{
    public void* handle;

    [NativeTypeName("ke_ecs_commands *")]
    public KernelEngine.Ecs.Native.ke_ecs_commands* commands;

    [NativeTypeName("const ke_ecs_segment *(*)(ke_system_ctx *, uint32_t, size_t *)")]
    public delegate* unmanaged[Cdecl]<ke_system_ctx*, uint, nuint*, KernelEngine.Ecs.Native.ke_ecs_segment*> view;

    [NativeTypeName("void (*)(ke_system_ctx *, uint32_t *, uint32_t *)")]
    public delegate* unmanaged[Cdecl]<ke_system_ctx*, uint*, uint*, void> slice;
}
