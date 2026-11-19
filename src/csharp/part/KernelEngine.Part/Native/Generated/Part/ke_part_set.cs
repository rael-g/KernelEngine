using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Part;

using KernelEngine.Completion.Native;
using KernelEngine.Result.Native;
using KernelEngine.Schedule.Native;
using KernelEngine.Settings.Native;

namespace KernelEngine.Part.Native;

public unsafe partial struct ke_part_set
{
    [NativeTypeName("const char *")]
    public sbyte* name;

    [NativeTypeName("const char *")]
    public sbyte* hook;

    [NativeTypeName("const char *")]
    public sbyte* after;
}
