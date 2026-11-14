using System.Numerics;

using global::KernelEngine.Ecs;

using KernelEngine.Completion.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Extraction.Native;

public unsafe partial struct ke_extraction
{
    public void* handle;

    [NativeTypeName("ke_result (*)(ke_extraction *, ke_component_id, ke_component_id)")]
    public delegate* unmanaged[Cdecl]<ke_extraction*, global::KernelEngine.Ecs.ComponentId, global::KernelEngine.Ecs.ComponentId, KernelEngine.Result.Native.Result> extract_copy;

    [NativeTypeName("ke_result (*)(ke_extraction *, ke_component_id, ke_component_id, ke_component_id, ke_extraction_interpolate_fn, void *)")]
    public delegate* unmanaged[Cdecl]<ke_extraction*, global::KernelEngine.Ecs.ComponentId, global::KernelEngine.Ecs.ComponentId, global::KernelEngine.Ecs.ComponentId, delegate* unmanaged[Cdecl]<void*, void*, void*, float, void*, void>, void*, KernelEngine.Result.Native.Result> extract_interpolate;

    [NativeTypeName("ke_result (*)(ke_extraction *, ke_extraction_custom_fn, void *)")]
    public delegate* unmanaged[Cdecl]<ke_extraction*, delegate* unmanaged[Cdecl]<void*, ke_extraction*, KernelEngine.Ecs.Native.ke_ecs*, KernelEngine.Ecs.Native.ke_ecs*, KernelEngine.Result.Native.Result>, void*, KernelEngine.Result.Native.Result> extract_custom;

    [NativeTypeName("ke_result (*)(ke_extraction *, ke_entity, ke_entity *)")]
    public delegate* unmanaged[Cdecl]<ke_extraction*, global::KernelEngine.Ecs.Entity, global::KernelEngine.Ecs.Entity*, KernelEngine.Result.Native.Result> render_entity;

    [NativeTypeName("ke_result (*)(ke_extraction *, ke_entity, ke_entity *)")]
    public delegate* unmanaged[Cdecl]<ke_extraction*, global::KernelEngine.Ecs.Entity, global::KernelEngine.Ecs.Entity*, KernelEngine.Result.Native.Result> main_entity;

    [NativeTypeName("ke_result (*)(ke_extraction *, float)")]
    public delegate* unmanaged[Cdecl]<ke_extraction*, float, KernelEngine.Result.Native.Result> extract;

    [NativeTypeName("ke_result (*)(ke_extraction *, float, ke_completion **)")]
    public delegate* unmanaged[Cdecl]<ke_extraction*, float, KernelEngine.Completion.Native.ke_completion**, KernelEngine.Result.Native.Result> run;
}
