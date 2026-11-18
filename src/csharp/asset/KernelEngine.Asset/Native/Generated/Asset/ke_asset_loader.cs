using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Render;

using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Asset.Native;

public unsafe partial struct ke_asset_loader
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_asset_loader *, const char *, ke_model_data **)")]
    public delegate* unmanaged[Cdecl]<ke_asset_loader*, sbyte*, ke_model_data**, KernelEngine.Result.Native.Result> load_model;

    [NativeTypeName("void (*)(struct ke_asset_loader *, ke_model_data *)")]
    public delegate* unmanaged[Cdecl]<ke_asset_loader*, ke_model_data*, void> free_model;
}
