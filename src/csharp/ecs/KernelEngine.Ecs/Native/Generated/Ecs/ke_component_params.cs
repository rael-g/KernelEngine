using KernelEngine.Common.Native;

namespace KernelEngine.Ecs.Native;

public unsafe partial struct ke_component_params
{
    [NativeTypeName("const char *")]
    public sbyte* name;

    [NativeTypeName("size_t")]
    public nuint size;

    [NativeTypeName("size_t")]
    public nuint alignment;

    [NativeTypeName("const ke_component_field *")]
    public ke_component_field* fields;

    [NativeTypeName("uint32_t")]
    public uint field_count;
}
