using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.TaskPool.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Asset.Native;

public unsafe partial struct ke_asset_resolver
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_asset_resolver *, const char *, ke_texture_data **)")]
    public delegate* unmanaged[Cdecl]<ke_asset_resolver*, sbyte*, ke_texture_data**, KernelEngine.Result.Native.ke_result> resolve_texture;

    [NativeTypeName("void (*)(struct ke_asset_resolver *, ke_texture_data *)")]
    public delegate* unmanaged[Cdecl]<ke_asset_resolver*, ke_texture_data*, void> free_texture;

    [NativeTypeName("ke_result (*)(struct ke_asset_resolver *, const char *, ke_mesh_shape_data **)")]
    public delegate* unmanaged[Cdecl]<ke_asset_resolver*, sbyte*, ke_mesh_shape_data**, KernelEngine.Result.Native.ke_result> resolve_mesh;

    [NativeTypeName("void (*)(struct ke_asset_resolver *, ke_mesh_shape_data *)")]
    public delegate* unmanaged[Cdecl]<ke_asset_resolver*, ke_mesh_shape_data*, void> free_mesh;

    [NativeTypeName("ke_result (*)(struct ke_asset_resolver *, const char *, ke_material_spec *)")]
    public delegate* unmanaged[Cdecl]<ke_asset_resolver*, sbyte*, KernelEngine.Render.Native.ke_material_spec*, KernelEngine.Result.Native.ke_result> resolve_material;

    [NativeTypeName("ke_result (*)(struct ke_asset_resolver *, const char *, float, uint32_t, uint32_t, uint32_t, ke_font_data **)")]
    public delegate* unmanaged[Cdecl]<ke_asset_resolver*, sbyte*, float, uint, uint, uint, KernelEngine.Text.Native.ke_font_data**, KernelEngine.Result.Native.ke_result> resolve_font;

    [NativeTypeName("void (*)(struct ke_asset_resolver *, ke_font_data *)")]
    public delegate* unmanaged[Cdecl]<ke_asset_resolver*, KernelEngine.Text.Native.ke_font_data*, void> free_font;

    [NativeTypeName("ke_result (*)(struct ke_asset_resolver *, ke_render_service *, const char *, ke_texture_handle *)")]
    public delegate* unmanaged[Cdecl]<ke_asset_resolver*, KernelEngine.Render.Native.ke_render_service*, sbyte*, KernelEngine.Render.Native.ke_texture_handle*, KernelEngine.Result.Native.ke_result> resolve_texture_into;

    [NativeTypeName("ke_result (*)(struct ke_asset_resolver *, ke_render_service *, const char *, ke_mesh_handle *)")]
    public delegate* unmanaged[Cdecl]<ke_asset_resolver*, KernelEngine.Render.Native.ke_render_service*, sbyte*, KernelEngine.Render.Native.ke_mesh_handle*, KernelEngine.Result.Native.ke_result> resolve_mesh_into;

    [NativeTypeName("ke_result (*)(struct ke_asset_resolver *, ke_render_service *, const char *, ke_material_handle *)")]
    public delegate* unmanaged[Cdecl]<ke_asset_resolver*, KernelEngine.Render.Native.ke_render_service*, sbyte*, KernelEngine.Render.Native.ke_material_handle*, KernelEngine.Result.Native.ke_result> resolve_material_into;

    [NativeTypeName("ke_result (*)(struct ke_asset_resolver *, const char *, char *, size_t)")]
    public delegate* unmanaged[Cdecl]<ke_asset_resolver*, sbyte*, sbyte*, nuint, KernelEngine.Result.Native.ke_result> resolve_path;
}
