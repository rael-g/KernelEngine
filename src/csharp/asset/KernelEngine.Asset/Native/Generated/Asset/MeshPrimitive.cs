using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Render;

using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.TaskPool.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Asset.Native;

[NativeTypeName("unsigned int")]
public enum MeshPrimitive : uint
{
    Quad = 0,
    Plane = 1,
    Cube = 2,
    Sphere = 3,
}
