using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Ecs;

public enum VariantType : uint
{
    Null = 0,
    Bool = 1,
    Int = 2,
    Float = 3,
    String = 4,
    Vec2 = 5,
    Vec3 = 6,
    Vec4 = 7,
    Quat = 8,
    Table = 9,
}
