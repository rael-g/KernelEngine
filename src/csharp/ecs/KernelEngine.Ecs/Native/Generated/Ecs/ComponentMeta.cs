using System.Numerics;

using global::KernelEngine.Ecs;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Ecs.Native;

public unsafe partial struct ComponentMeta
{
    [NativeTypeName("ke_component_id")]
    public global::KernelEngine.Ecs.ComponentId Cid;

    [NativeTypeName("size_t")]
    public nuint Size;

    [NativeTypeName("size_t")]
    public nuint Alignment;

    [NativeTypeName("const ke_component_field *")]
    public ke_component_field* Fields;

    [NativeTypeName("uint32_t")]
    public uint FieldCount;
}
