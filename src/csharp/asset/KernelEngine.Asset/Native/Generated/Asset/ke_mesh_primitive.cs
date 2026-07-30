using KernelEngine.Common.Native;

namespace KernelEngine.Asset.Native;

[NativeTypeName("unsigned int")]
public enum ke_mesh_primitive : uint
{
    KE_MESH_PRIMITIVE_QUAD = 0,
    KE_MESH_PRIMITIVE_PLANE = 1,
    KE_MESH_PRIMITIVE_CUBE = 2,
    KE_MESH_PRIMITIVE_SPHERE = 3,
}
