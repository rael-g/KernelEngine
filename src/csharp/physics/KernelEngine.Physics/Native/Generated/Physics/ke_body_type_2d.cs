using KernelEngine.Common.Native;

namespace KernelEngine.Physics.Native;

[NativeTypeName("unsigned int")]
public enum ke_body_type_2d : uint
{
    KE_BODY_TYPE_STATIC = 0,
    KE_BODY_TYPE_KINEMATIC = 1,
    KE_BODY_TYPE_DYNAMIC = 2,
}
