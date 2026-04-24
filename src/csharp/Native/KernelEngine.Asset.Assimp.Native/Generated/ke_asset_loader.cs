using KernelEngine.Kernel.Native;

namespace KernelEngine.Asset.Assimp.Native;

/// <summary>ABI-stable vtable for loading 3D assets.</summary>
public unsafe partial struct ke_asset_loader
{
    public void* handle;

    [NativeTypeName("void (*)(struct ke_asset_loader *)")]
    public delegate* unmanaged[Cdecl]<ke_asset_loader*, void> destroy;

    [NativeTypeName("ke_result (*)(struct ke_asset_loader *, const char *, ke_model_data **)")]
    public delegate* unmanaged[Cdecl]<ke_asset_loader*, sbyte*, ke_model_data**, ke_result> load_model;

    [NativeTypeName("void (*)(struct ke_asset_loader *, ke_model_data *)")]
    public delegate* unmanaged[Cdecl]<ke_asset_loader*, ke_model_data*, void> free_model;

    [NativeTypeName("ke_task *(*)(struct ke_asset_loader *, ke_task_scheduler *, const char *, ke_load_model_complete_func, void *)")]
    public delegate* unmanaged[Cdecl]<ke_asset_loader*, ke_task_scheduler*, sbyte*, delegate* unmanaged[Cdecl]<ke_result, ke_model_data*, void*, void>, void*, ke_task*> load_model_async;
}
