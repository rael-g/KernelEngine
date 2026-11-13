using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Ecs;

public enum EcsAccess : uint
{
    Read = 1 << 0,
    Write = 1 << 1,
}
