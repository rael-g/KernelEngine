namespace KernelEngine.Kernel.Native;

public partial struct ke_transform_component
{
    public ke_vec3 position;

    public ke_quat rotation;

    public ke_vec3 scale;

    public ke_mat4 world_matrix;
}
