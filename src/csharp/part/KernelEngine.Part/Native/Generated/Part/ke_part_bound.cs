using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Part;

using KernelEngine.Completion.Native;
using KernelEngine.Result.Native;
using KernelEngine.Schedule.Native;
using KernelEngine.Settings.Native;

namespace KernelEngine.Part.Native;

public unsafe partial struct ke_part_bound
{
    [NativeTypeName("void *const *")]
    public void** instances;

    [NativeTypeName("const size_t *")]
    public nuint* positions;

    [NativeTypeName("size_t")]
    public nuint count;
}
