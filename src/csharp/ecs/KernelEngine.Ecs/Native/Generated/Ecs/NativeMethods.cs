using KernelEngine.Common.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Ecs.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_ecs_flecs", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_ecs_registry_create", ExactSpelling = true)]
    public static extern bool ecs_registry_create(ke_ecs_registry** out_registry, ke_error** out_error);

    [DllImport("ke_ecs_flecs", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_ecs_registry_destroy", ExactSpelling = true)]
    public static extern void ecs_registry_destroy(ke_ecs_registry* registry);

    [DllImport("ke_ecs_flecs", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_ecs_entity_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_entity")]
    public static extern ulong ecs_entity_create(ke_ecs_registry* registry);

    [DllImport("ke_ecs_flecs", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_ecs_entity_destroy", ExactSpelling = true)]
    public static extern void ecs_entity_destroy(ke_ecs_registry* registry, [NativeTypeName("ke_entity")] ulong entity);

    [DllImport("ke_ecs_flecs", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_ecs_component_register", ExactSpelling = true)]
    [return: NativeTypeName("ke_component_id")]
    public static extern uint ecs_component_register(ke_ecs_registry* registry, [NativeTypeName("const char *")] sbyte* name, [NativeTypeName("size_t")] nuint size);

    [DllImport("ke_ecs_flecs", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_ecs_component_register_v2", ExactSpelling = true)]
    [return: NativeTypeName("ke_component_id")]
    public static extern uint ecs_component_register_v2(ke_ecs_registry* registry, [NativeTypeName("const char *")] sbyte* name, [NativeTypeName("size_t")] nuint size, [NativeTypeName("const ke_component_field *")] ke_component_field* fields, [NativeTypeName("uint32_t")] uint field_count);

    [DllImport("ke_ecs_flecs", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_ecs_component_lookup", ExactSpelling = true)]
    public static extern bool ecs_component_lookup(ke_ecs_registry* registry, [NativeTypeName("const char *")] sbyte* name, ke_component_meta* out_meta, ke_error** out_error);

    [DllImport("ke_ecs_flecs", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_ecs_component_apply_variant", ExactSpelling = true)]
    public static extern bool ecs_component_apply_variant(ke_ecs_registry* registry, [NativeTypeName("ke_entity")] ulong entity, [NativeTypeName("ke_component_id")] uint cid, [NativeTypeName("const char *")] sbyte* field_name, [NativeTypeName("const ke_variant *")] ke_variant* value, ke_error** out_error);

    [DllImport("ke_ecs_flecs", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_ecs_component_add", ExactSpelling = true)]
    public static extern void* ecs_component_add(ke_ecs_registry* registry, [NativeTypeName("ke_entity")] ulong entity, [NativeTypeName("ke_component_id")] uint component);

    [DllImport("ke_ecs_flecs", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_ecs_component_remove", ExactSpelling = true)]
    public static extern void ecs_component_remove(ke_ecs_registry* registry, [NativeTypeName("ke_entity")] ulong entity, [NativeTypeName("ke_component_id")] uint component);

    [DllImport("ke_ecs_flecs", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_ecs_component_get", ExactSpelling = true)]
    public static extern void* ecs_component_get(ke_ecs_registry* registry, [NativeTypeName("ke_entity")] ulong entity, [NativeTypeName("ke_component_id")] uint component);

    [DllImport("ke_ecs_flecs", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_ecs_registry_query", ExactSpelling = true)]
    public static extern void ecs_registry_query(ke_ecs_registry* registry, [NativeTypeName("ke_component_id")] uint component, [NativeTypeName("ke_entity **")] ulong** out_entities, void** out_data, [NativeTypeName("size_t *")] nuint* out_count);
}
