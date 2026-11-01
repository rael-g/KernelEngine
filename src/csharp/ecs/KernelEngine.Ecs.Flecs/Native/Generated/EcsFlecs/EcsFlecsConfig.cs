using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;

using KernelEngine.Ecs.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Ecs.Flecs.Native;

public partial struct EcsFlecsConfig
{
    [NativeTypeName("uint32_t")]
    public uint WorldIdBase;
}
