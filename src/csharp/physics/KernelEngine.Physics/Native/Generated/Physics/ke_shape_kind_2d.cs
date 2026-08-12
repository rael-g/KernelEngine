using KernelEngine.Common.Native;

namespace KernelEngine.Physics.Native;

[NativeTypeName("unsigned int")]
public enum ke_shape_kind_2d : uint
{
    KE_SHAPE_KIND_2D_BOX = 0,
    KE_SHAPE_KIND_2D_CIRCLE = 1,
}
