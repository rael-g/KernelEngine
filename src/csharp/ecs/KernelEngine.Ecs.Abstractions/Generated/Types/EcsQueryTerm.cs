using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Ecs;

public partial struct EcsQueryTerm
{
    public global::KernelEngine.Ecs.ComponentId Component;
    public EcsAccess Access;
}
