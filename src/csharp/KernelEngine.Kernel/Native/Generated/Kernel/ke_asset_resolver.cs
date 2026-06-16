namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_asset_resolver
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_asset_resolver *, const char *, ke_texture_data **)")]
    public delegate* unmanaged[Cdecl]<ke_asset_resolver*, sbyte*, ke_texture_data**, int> resolve_texture;

    [NativeTypeName("void (*)(struct ke_asset_resolver *, ke_texture_data *)")]
    public delegate* unmanaged[Cdecl]<ke_asset_resolver*, ke_texture_data*, void> free_texture;

    [NativeTypeName("ke_result (*)(struct ke_asset_resolver *, const char *, ke_mesh_shape_data *)")]
    public delegate* unmanaged[Cdecl]<ke_asset_resolver*, sbyte*, ke_mesh_shape_data*, int> resolve_mesh;

    [NativeTypeName("void (*)(struct ke_asset_resolver *, ke_mesh_shape_data *)")]
    public delegate* unmanaged[Cdecl]<ke_asset_resolver*, ke_mesh_shape_data*, void> free_mesh;

    [NativeTypeName("ke_result (*)(struct ke_asset_resolver *, const char *, ke_material_spec *)")]
    public delegate* unmanaged[Cdecl]<ke_asset_resolver*, sbyte*, ke_material_spec*, int> resolve_material;

    [NativeTypeName("ke_result (*)(struct ke_asset_resolver *, const char *, float, uint32_t, uint32_t, uint32_t, ke_font_data **)")]
    public delegate* unmanaged[Cdecl]<ke_asset_resolver*, sbyte*, float, uint, uint, uint, ke_font_data**, int> resolve_font;

    [NativeTypeName("void (*)(struct ke_asset_resolver *, ke_font_data *)")]
    public delegate* unmanaged[Cdecl]<ke_asset_resolver*, ke_font_data*, void> free_font;

    [NativeTypeName("void (*)(struct ke_asset_resolver *)")]
    public delegate* unmanaged[Cdecl]<ke_asset_resolver*, void> destroy;
}
