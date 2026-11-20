using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Logger;
using global::KernelEngine.Render;

using KernelEngine.Common.Native;
using KernelEngine.Part.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.View.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_view_space", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_view_space_lh_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result view_space_lh_create(ke_view_space_handle* out_view_space);

    [DllImport("ke_view_space", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_view_space_set_log_callback", ExactSpelling = true)]
    public static extern void view_space_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);

    [DllImport("ke_view_space", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_view_space_parts", ExactSpelling = true)]
    [return: NativeTypeName("const ke_part *")]
    public static extern KernelEngine.Part.Native.ke_part* view_space_parts([NativeTypeName("size_t *")] nuint* out_count);
}
