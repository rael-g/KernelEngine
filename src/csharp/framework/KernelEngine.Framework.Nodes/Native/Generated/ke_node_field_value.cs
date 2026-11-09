using System.Numerics;

using global::KernelEngine.Common;
using global::KernelEngine.Ecs;
using global::KernelEngine.Physics;
using global::KernelEngine.Render;

using KernelEngine.Asset.Native;
using KernelEngine.Audio.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Framework.Native;
using KernelEngine.Io.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;

namespace KernelEngine.Framework.Nodes.Native;

public unsafe partial struct ke_node_field_value
{
    [NativeTypeName("const char *")]
    public sbyte* component;

    [NativeTypeName("const char *")]
    public sbyte* field;

    [NativeTypeName("ke_variant")]
    public KernelEngine.Ecs.Native.Variant value;
}
