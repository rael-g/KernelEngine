using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Logger;

using KernelEngine.Asset.Native;
using KernelEngine.Io.Native;
using KernelEngine.Part.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Asset.Assimp.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_asset_assimp", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_asset_loader_assimp_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result asset_loader_assimp_create([NativeTypeName("ke_io *")] KernelEngine.Io.Native.ke_io* io, [NativeTypeName("ke_asset_loader_handle *")] KernelEngine.Asset.Native.ke_asset_loader_handle* out_loader);

    [DllImport("ke_asset_assimp", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_asset_assimp_parts", ExactSpelling = true)]
    [return: NativeTypeName("const ke_part *")]
    public static extern KernelEngine.Part.Native.ke_part* asset_assimp_parts([NativeTypeName("size_t *")] nuint* out_count);

    [DllImport("ke_asset_assimp", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_asset_assimp_set_log_callback", ExactSpelling = true)]
    public static extern void asset_assimp_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
