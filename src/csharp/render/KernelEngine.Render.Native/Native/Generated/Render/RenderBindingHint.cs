using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Render;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Native;

public unsafe partial struct RenderBindingHint
{
    [NativeTypeName("const char *")]
    public sbyte* Name;

    [NativeTypeName("uint32_t")]
    public uint Flags;
}
