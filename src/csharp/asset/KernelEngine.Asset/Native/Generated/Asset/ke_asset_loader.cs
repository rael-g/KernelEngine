using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Render;

using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.TaskPool.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Asset.Native;

public unsafe partial struct ke_asset_loader
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_asset_loader *, const char *, ke_model_data **)")]
    public delegate* unmanaged[Cdecl]<ke_asset_loader*, sbyte*, ke_model_data**, KernelEngine.Result.Native.Result> load_model;

    [NativeTypeName("void (*)(struct ke_asset_loader *, ke_model_data *)")]
    public delegate* unmanaged[Cdecl]<ke_asset_loader*, ke_model_data*, void> free_model;

    [NativeTypeName("ke_task *(*)(struct ke_asset_loader *, ke_task_pool *, const char *, ke_load_model_complete_func, void *)")]
    public delegate* unmanaged[Cdecl]<ke_asset_loader*, KernelEngine.TaskPool.Native.ke_task_pool*, sbyte*, delegate* unmanaged[Cdecl]<KernelEngine.Result.Native.Result, ke_model_data*, void*, void>, void*, KernelEngine.TaskPool.Native.ke_task*> load_model_async;
}
