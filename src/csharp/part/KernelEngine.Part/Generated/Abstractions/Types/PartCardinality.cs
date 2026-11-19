using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Part;

public enum PartCardinality : uint
{
    One = 1,
    Optional = 2,
    Many = 3,
}
