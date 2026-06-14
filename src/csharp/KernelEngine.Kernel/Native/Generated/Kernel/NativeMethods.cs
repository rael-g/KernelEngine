using System;
using System.Runtime.InteropServices;

namespace KernelEngine.Kernel.Native;

public static unsafe partial class NativeMethods
{
    [NativeTypeName("#define KE_HANDLE_NONE UINT32_MAX")]
    public const uint KE_HANDLE_NONE = 0xffffffffU;

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_hash_string", ExactSpelling = true)]
    [return: NativeTypeName("uint64_t")]
    public static extern ulong hash_string([NativeTypeName("const char *")] sbyte* str);

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_hash_map_init", ExactSpelling = true)]
    public static extern ke_result hash_map_init(ke_hash_map* map, [NativeTypeName("size_t")] nuint initial_capacity, [NativeTypeName("struct ke_allocator *")] ke_allocator* alloc);

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_hash_map_destroy", ExactSpelling = true)]
    public static extern void hash_map_destroy(ke_hash_map* map);

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_hash_map_insert", ExactSpelling = true)]
    public static extern ke_result hash_map_insert(ke_hash_map* map, [NativeTypeName("uint64_t")] ulong key, void* value);

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_hash_map_get", ExactSpelling = true)]
    public static extern void* hash_map_get([NativeTypeName("const ke_hash_map *")] ke_hash_map* map, [NativeTypeName("uint64_t")] ulong key);

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_allocator_malloc_create", ExactSpelling = true)]
    public static extern ke_allocator* allocator_malloc_create();

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_allocator_arena_create", ExactSpelling = true)]
    public static extern ke_allocator* allocator_arena_create([NativeTypeName("size_t")] nuint fixed_capacity);

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_allocator_proxy_create", ExactSpelling = true)]
    public static extern ke_allocator* allocator_proxy_create(ke_allocator* inner, [NativeTypeName("const char *")] sbyte* name);

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_allocator_proxy_get_stats", ExactSpelling = true)]
    public static extern ke_result allocator_proxy_get_stats(ke_allocator* proxy, ke_allocator_stats* out_stats);

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_allocator_proxy_report", ExactSpelling = true)]
    public static extern void allocator_proxy_report(ke_allocator* proxy, [NativeTypeName("struct ke_logger *")] ke_logger* logger);

    [NativeTypeName("#define KE_ID_ALLOCATOR_DEFAULT \"ke_alloc_default\"")]
    public static ReadOnlySpan<byte> KE_ID_ALLOCATOR_DEFAULT => "ke_alloc_default"u8;

    [NativeTypeName("#define KE_ID_ALLOCATOR_SCRATCH \"ke_alloc_scratch\"")]
    public static ReadOnlySpan<byte> KE_ID_ALLOCATOR_SCRATCH => "ke_alloc_scratch"u8;

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_log_level_to_string", ExactSpelling = true)]
    [return: NativeTypeName("const char *")]
    public static extern sbyte* log_level_to_string([NativeTypeName("int32_t")] int level);

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_logger_create", ExactSpelling = true)]
    public static extern ke_result logger_create(ke_allocator* allocator, ke_logger** out_logger);

    [NativeTypeName("#define KE_ID_LOGGER \"ke_logger\"")]
    public static ReadOnlySpan<byte> KE_ID_LOGGER => "ke_logger"u8;

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_ecs_registry_create", ExactSpelling = true)]
    public static extern ke_result ecs_registry_create([NativeTypeName("struct ke_allocator *")] ke_allocator* alloc, ke_ecs_registry** out_registry);

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_ecs_registry_destroy", ExactSpelling = true)]
    public static extern void ecs_registry_destroy(ke_ecs_registry* registry);

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_ecs_entity_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_entity")]
    public static extern ulong ecs_entity_create(ke_ecs_registry* registry);

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_ecs_entity_destroy", ExactSpelling = true)]
    public static extern void ecs_entity_destroy(ke_ecs_registry* registry, [NativeTypeName("ke_entity")] ulong entity);

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_ecs_component_register", ExactSpelling = true)]
    [return: NativeTypeName("ke_component_id")]
    public static extern uint ecs_component_register(ke_ecs_registry* registry, [NativeTypeName("const char *")] sbyte* name, [NativeTypeName("size_t")] nuint size);

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_ecs_component_register_v2", ExactSpelling = true)]
    [return: NativeTypeName("ke_component_id")]
    public static extern uint ecs_component_register_v2(ke_ecs_registry* registry, [NativeTypeName("const char *")] sbyte* name, [NativeTypeName("size_t")] nuint size, [NativeTypeName("const ke_component_field *")] ke_component_field* fields, [NativeTypeName("uint32_t")] uint field_count);

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_ecs_component_lookup", ExactSpelling = true)]
    public static extern ke_result ecs_component_lookup(ke_ecs_registry* registry, [NativeTypeName("const char *")] sbyte* name, ke_component_meta* out_meta);

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_ecs_component_apply_variant", ExactSpelling = true)]
    public static extern ke_result ecs_component_apply_variant(ke_ecs_registry* registry, [NativeTypeName("ke_entity")] ulong entity, [NativeTypeName("ke_component_id")] uint cid, [NativeTypeName("const char *")] sbyte* field_name, [NativeTypeName("const ke_variant *")] ke_variant* value);

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_ecs_component_add", ExactSpelling = true)]
    public static extern void* ecs_component_add(ke_ecs_registry* registry, [NativeTypeName("ke_entity")] ulong entity, [NativeTypeName("ke_component_id")] uint component);

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_ecs_component_remove", ExactSpelling = true)]
    public static extern void ecs_component_remove(ke_ecs_registry* registry, [NativeTypeName("ke_entity")] ulong entity, [NativeTypeName("ke_component_id")] uint component);

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_ecs_component_get", ExactSpelling = true)]
    public static extern void* ecs_component_get(ke_ecs_registry* registry, [NativeTypeName("ke_entity")] ulong entity, [NativeTypeName("ke_component_id")] uint component);

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_ecs_registry_query", ExactSpelling = true)]
    public static extern void ecs_registry_query(ke_ecs_registry* registry, [NativeTypeName("ke_component_id")] uint component, [NativeTypeName("ke_entity **")] ulong** out_entities, void** out_data, [NativeTypeName("size_t *")] nuint* out_count);

    [NativeTypeName("#define KE_ENTITY_INVALID 0")]
    public const int KE_ENTITY_INVALID = 0;

    [NativeTypeName("#define KE_COMPONENT_INVALID ((ke_component_id)-1)")]
    public const uint KE_COMPONENT_INVALID = unchecked((uint)(-1));

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_ecs_sparse_set_create", ExactSpelling = true)]
    public static extern ke_result ecs_sparse_set_create(ke_ecs_registry* registry, ke_allocator* alloc, ke_ecs** out_ecs);

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_resource_cache_create", ExactSpelling = true)]
    public static extern ke_result resource_cache_create([NativeTypeName("const ke_resource_cache_params *")] ke_resource_cache_params* @params, ke_resource_cache** out_cache);

    [NativeTypeName("#define KE_RESOURCE_HANDLE_NONE UINT32_MAX")]
    public const uint KE_RESOURCE_HANDLE_NONE = 0xffffffffU;

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_input_create", ExactSpelling = true)]
    public static extern ke_result input_create([NativeTypeName("struct ke_allocator *")] ke_allocator* allocator, [NativeTypeName("struct ke_logger *")] ke_logger* logger, ke_input** out_input);

    [NativeTypeName("#define KE_ID_INPUT \"ke_input\"")]
    public static ReadOnlySpan<byte> KE_ID_INPUT => "ke_input"u8;

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_frame_packet_create", ExactSpelling = true)]
    public static extern ke_result frame_packet_create([NativeTypeName("const ke_frame_packet_params *")] ke_frame_packet_params* @params, ke_frame_packet** out_packet);

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_frame_packet_destroy", ExactSpelling = true)]
    public static extern void frame_packet_destroy([NativeTypeName("struct ke_allocator *")] ke_allocator* allocator, ke_frame_packet* packet);

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_frame_packet_reset", ExactSpelling = true)]
    public static extern void frame_packet_reset(ke_frame_packet* packet);

    [NativeTypeName("#define KE_ID_RENDER \"ke_render\"")]
    public static ReadOnlySpan<byte> KE_ID_RENDER => "ke_render"u8;

    [NativeTypeName("#define KE_ID_RENDER_GRAPH \"ke_render_graph\"")]
    public static ReadOnlySpan<byte> KE_ID_RENDER_GRAPH => "ke_render_graph"u8;

    [NativeTypeName("#define KE_ID_SHADER_COMPILER \"ke_shader_compiler\"")]
    public static ReadOnlySpan<byte> KE_ID_SHADER_COMPILER => "ke_shader_compiler"u8;

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_thread_set_current_name", ExactSpelling = true)]
    public static extern void thread_set_current_name([NativeTypeName("const char *")] sbyte* name);

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_thread_get_current_name", ExactSpelling = true)]
    [return: NativeTypeName("const char *")]
    public static extern sbyte* thread_get_current_name();

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_thread_assert_current", ExactSpelling = true)]
    public static extern void thread_assert_current([NativeTypeName("const char *")] sbyte* expected_name);

    [NativeTypeName("#define KE_ID_WINDOW \"ke_window\"")]
    public static ReadOnlySpan<byte> KE_ID_WINDOW => "ke_window"u8;

    [NativeTypeName("#define KE_ID_AUDIO \"ke_audio\"")]
    public static ReadOnlySpan<byte> KE_ID_AUDIO => "ke_audio"u8;

    [NativeTypeName("#define KE_AUDIO_SOUND_INVALID ((ke_audio_sound)0)")]
    public const uint KE_AUDIO_SOUND_INVALID = ((uint)(0));

    [NativeTypeName("#define KE_ID_PHYSICS_2D \"ke_physics_2d\"")]
    public static ReadOnlySpan<byte> KE_ID_PHYSICS_2D => "ke_physics_2d"u8;

    [NativeTypeName("#define KE_BODY_2D_INVALID ((ke_body_2d)0)")]
    public const uint KE_BODY_2D_INVALID = ((uint)(0));

    [NativeTypeName("#define KE_ID_FONT_LOADER \"ke_font_loader\"")]
    public static ReadOnlySpan<byte> KE_ID_FONT_LOADER => "ke_font_loader"u8;

    [NativeTypeName("#define KE_COMPONENT_NAME_TRANSFORM \"transform\"")]
    public static ReadOnlySpan<byte> KE_COMPONENT_NAME_TRANSFORM => "transform"u8;

    [NativeTypeName("#define KE_COMPONENT_NAME_HIERARCHY \"hierarchy\"")]
    public static ReadOnlySpan<byte> KE_COMPONENT_NAME_HIERARCHY => "hierarchy"u8;

    [NativeTypeName("#define KE_COMPONENT_NAME_NAME \"name\"")]
    public static ReadOnlySpan<byte> KE_COMPONENT_NAME_NAME => "name"u8;

    [NativeTypeName("#define KE_COMPONENT_NAME_CAMERA \"camera\"")]
    public static ReadOnlySpan<byte> KE_COMPONENT_NAME_CAMERA => "camera"u8;

    [NativeTypeName("#define KE_COMPONENT_NAME_DIRECTIONAL_LIGHT \"directional_light\"")]
    public static ReadOnlySpan<byte> KE_COMPONENT_NAME_DIRECTIONAL_LIGHT => "directional_light"u8;

    [NativeTypeName("#define KE_COMPONENT_NAME_POINT_LIGHT \"point_light\"")]
    public static ReadOnlySpan<byte> KE_COMPONENT_NAME_POINT_LIGHT => "point_light"u8;

    [NativeTypeName("#define KE_COMPONENT_NAME_SPOT_LIGHT \"spot_light\"")]
    public static ReadOnlySpan<byte> KE_COMPONENT_NAME_SPOT_LIGHT => "spot_light"u8;

    [NativeTypeName("#define KE_COMPONENT_NAME_MESH \"mesh\"")]
    public static ReadOnlySpan<byte> KE_COMPONENT_NAME_MESH => "mesh"u8;

    [NativeTypeName("#define KE_SCENE_PROPERTIES_COMPONENT_NAME \"scene_properties\"")]
    public static ReadOnlySpan<byte> KE_SCENE_PROPERTIES_COMPONENT_NAME => "scene_properties"u8;

    [NativeTypeName("#define KE_MATERIAL_PATH_MAX 256")]
    public const int KE_MATERIAL_PATH_MAX = 256;
}
