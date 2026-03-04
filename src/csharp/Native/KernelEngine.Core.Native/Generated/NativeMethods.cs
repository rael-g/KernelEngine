using System;
using System.Runtime.InteropServices;

namespace KernelEngine.Core.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_core", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_hash_string", ExactSpelling = true)]
    [return: NativeTypeName("uint64_t")]
    public static extern ulong hash_string([NativeTypeName("const char *")] sbyte* str);

    [DllImport("ke_core", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_hash_map_init", ExactSpelling = true)]
    public static extern ke_result hash_map_init(ke_hash_map* map, [NativeTypeName("size_t")] nuint initial_capacity, [NativeTypeName("struct ke_allocator *")] ke_allocator* alloc);

    [DllImport("ke_core", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_hash_map_destroy", ExactSpelling = true)]
    public static extern void hash_map_destroy(ke_hash_map* map);

    [DllImport("ke_core", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_hash_map_insert", ExactSpelling = true)]
    public static extern ke_result hash_map_insert(ke_hash_map* map, [NativeTypeName("uint64_t")] ulong key, void* value);

    [DllImport("ke_core", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_hash_map_get", ExactSpelling = true)]
    public static extern void* hash_map_get([NativeTypeName("const ke_hash_map *")] ke_hash_map* map, [NativeTypeName("uint64_t")] ulong key);

    [DllImport("ke_core", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_allocator_malloc_create", ExactSpelling = true)]
    public static extern ke_allocator* allocator_malloc_create();

    [DllImport("ke_core", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_allocator_arena_create", ExactSpelling = true)]
    public static extern ke_allocator* allocator_arena_create([NativeTypeName("size_t")] nuint fixed_capacity);

    [NativeTypeName("#define KE_ID_ALLOCATOR_DEFAULT \"ke_alloc_default\"")]
    public static ReadOnlySpan<byte> KE_ID_ALLOCATOR_DEFAULT => "ke_alloc_default"u8;

    [NativeTypeName("#define KE_ID_ALLOCATOR_SCRATCH \"ke_alloc_scratch\"")]
    public static ReadOnlySpan<byte> KE_ID_ALLOCATOR_SCRATCH => "ke_alloc_scratch"u8;

    [DllImport("ke_core", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_log_level_to_string", ExactSpelling = true)]
    [return: NativeTypeName("const char *")]
    public static extern sbyte* log_level_to_string(int level);

    [DllImport("ke_core", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_logger_create", ExactSpelling = true)]
    public static extern ke_result logger_create([NativeTypeName("const ke_descriptor *")] ke_descriptor* desc, ke_logger** out_logger);

    [NativeTypeName("#define KE_ID_LOGGER \"ke_logger\"")]
    public static ReadOnlySpan<byte> KE_ID_LOGGER => "ke_logger"u8;

    [DllImport("ke_core", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_message_pipe_create", ExactSpelling = true)]
    public static extern ke_result message_pipe_create([NativeTypeName("const ke_descriptor *")] ke_descriptor* desc, ke_message_pipe** out_pipe);

    [NativeTypeName("#define KE_ID_MESSAGE_PIPE \"ke_message_pipe\"")]
    public static ReadOnlySpan<byte> KE_ID_MESSAGE_PIPE => "ke_message_pipe"u8;

    [DllImport("ke_core", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_engine_create", ExactSpelling = true)]
    public static extern ke_result engine_create([NativeTypeName("const ke_descriptor *")] ke_descriptor* desc, ke_engine** out_engine);

    [NativeTypeName("#define KE_ID_ENGINE \"ke_engine\"")]
    public static ReadOnlySpan<byte> KE_ID_ENGINE => "ke_engine"u8;

    public const int KE_MSG_KEY_EVENT = 0x1001;

    [DllImport("ke_core", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_input_create", ExactSpelling = true)]
    public static extern ke_result input_create([NativeTypeName("const ke_descriptor *")] ke_descriptor* desc, ke_input** out_input);

    [NativeTypeName("#define KE_ID_INPUT \"ke_input\"")]
    public static ReadOnlySpan<byte> KE_ID_INPUT => "ke_input"u8;

    [NativeTypeName("#define KE_ID_RENDER \"ke_render\"")]
    public static ReadOnlySpan<byte> KE_ID_RENDER => "ke_render"u8;

    [DllImport("ke_core", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_shader_compiler_bgfx_create", ExactSpelling = true)]
    public static extern ke_result shader_compiler_bgfx_create([NativeTypeName("const ke_shader_compiler_bgfx_descriptor *")] ke_shader_compiler_bgfx_descriptor* desc, ke_system** out_system);

    [NativeTypeName("#define KE_ID_SHADER_COMPILER \"ke_shader_compiler\"")]
    public static ReadOnlySpan<byte> KE_ID_SHADER_COMPILER => "ke_shader_compiler"u8;

    [NativeTypeName("#define KE_ID_WINDOW \"ke_window\"")]
    public static ReadOnlySpan<byte> KE_ID_WINDOW => "ke_window"u8;
}
