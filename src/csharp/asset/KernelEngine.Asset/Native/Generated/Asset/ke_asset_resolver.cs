using KernelEngine.Common.Native;

namespace KernelEngine.Asset.Native;

public unsafe partial struct ke_asset_resolver
{
    public void* handle;

    [NativeTypeName("bool (*)(struct ke_asset_resolver *, const char *, ke_texture_data **, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_asset_resolver*, sbyte*, ke_texture_data**, ke_error**, bool> resolve_texture;

    [NativeTypeName("void (*)(struct ke_asset_resolver *, ke_texture_data *)")]
    public delegate* unmanaged[Cdecl]<ke_asset_resolver*, ke_texture_data*, void> free_texture;

    [NativeTypeName("bool (*)(struct ke_asset_resolver *, const char *, ke_mesh_shape_data *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_asset_resolver*, sbyte*, ke_mesh_shape_data*, ke_error**, bool> resolve_mesh;

    [NativeTypeName("void (*)(struct ke_asset_resolver *, ke_mesh_shape_data *)")]
    public delegate* unmanaged[Cdecl]<ke_asset_resolver*, ke_mesh_shape_data*, void> free_mesh;

    [NativeTypeName("bool (*)(struct ke_asset_resolver *, const char *, ke_material_spec *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_asset_resolver*, sbyte*, KernelEngine.Render.Native.ke_material_spec*, ke_error**, bool> resolve_material;

    [NativeTypeName("bool (*)(struct ke_asset_resolver *, const char *, float, uint32_t, uint32_t, uint32_t, ke_font_data **, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_asset_resolver*, sbyte*, float, uint, uint, uint, KernelEngine.Text.Native.ke_font_data**, ke_error**, bool> resolve_font;

    [NativeTypeName("void (*)(struct ke_asset_resolver *, ke_font_data *)")]
    public delegate* unmanaged[Cdecl]<ke_asset_resolver*, KernelEngine.Text.Native.ke_font_data*, void> free_font;
}
