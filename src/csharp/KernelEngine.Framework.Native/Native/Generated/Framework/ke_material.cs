namespace KernelEngine.Framework.Native;

public partial struct ke_material
{
    public float r;

    public float g;

    public float b;

    public float a;

    public ke_texture_handle albedo;

    public float metallic;

    public float roughness;

    public ke_texture_handle normal_map;
}
