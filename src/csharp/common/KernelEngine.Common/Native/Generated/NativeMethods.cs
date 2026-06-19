using System;
using System.Runtime.InteropServices;

namespace KernelEngine.Common.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_alloc", ExactSpelling = true)]
    public static extern void* alloc([NativeTypeName("size_t")] nuint size, [NativeTypeName("size_t")] nuint alignment);

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_free", ExactSpelling = true)]
    public static extern void free(void* ptr);

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_realloc", ExactSpelling = true)]
    public static extern void* realloc(void* ptr, [NativeTypeName("size_t")] nuint new_size);

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_arena_init", ExactSpelling = true)]
    public static extern void arena_init(ke_arena* arena, [NativeTypeName("size_t")] nuint capacity);

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_arena_alloc", ExactSpelling = true)]
    public static extern void* arena_alloc(ke_arena* arena, [NativeTypeName("size_t")] nuint size, [NativeTypeName("size_t")] nuint alignment);

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_arena_reset", ExactSpelling = true)]
    public static extern void arena_reset(ke_arena* arena);

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_arena_destroy", ExactSpelling = true)]
    public static extern void arena_destroy(ke_arena* arena);

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_resource_cache_create", ExactSpelling = true)]
    public static extern ke_result resource_cache_create([NativeTypeName("const ke_resource_cache_params *")] ke_resource_cache_params* @params, ke_resource_cache_handle* out_cache, ke_error** out_error);

    [NativeTypeName("#define KE_RESOURCE_HANDLE_NONE UINT32_MAX")]
    public const uint KE_RESOURCE_HANDLE_NONE = 0xffffffffU;

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_thread_set_current_name", ExactSpelling = true)]
    public static extern void thread_set_current_name([NativeTypeName("const char *")] sbyte* name);

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_thread_get_current_name", ExactSpelling = true)]
    [return: NativeTypeName("const char *")]
    public static extern sbyte* thread_get_current_name();

    [DllImport("ke_kernel", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_thread_assert_current", ExactSpelling = true)]
    public static extern void thread_assert_current([NativeTypeName("const char *")] sbyte* expected_name);

    [NativeTypeName("#define KE_COMPONENT_NAME_TRANSFORM \"transform\"")]
    public static ReadOnlySpan<byte> KE_COMPONENT_NAME_TRANSFORM => "transform"u8;
}
