using KernelEngine.Common.Native;

namespace KernelEngine.Ecs.Native;

[NativeTypeName("unsigned int")]
public enum ke_variant_type : uint
{
    KE_VARIANT_NULL = 0,
    KE_VARIANT_BOOL = 1,
    KE_VARIANT_INT = 2,
    KE_VARIANT_FLOAT = 3,
    KE_VARIANT_STRING = 4,
    KE_VARIANT_VEC2 = 5,
    KE_VARIANT_VEC3 = 6,
    KE_VARIANT_VEC4 = 7,
    KE_VARIANT_QUAT = 8,
    KE_VARIANT_TABLE = 9,
}
