using System.Runtime.InteropServices;

using KernelEngine.Asset.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Asset.Assimp.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_asset_assimp", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_asset_loader_assimp_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.ke_result asset_loader_assimp_create([NativeTypeName("ke_asset_loader_handle *")] KernelEngine.Asset.Native.ke_asset_loader_handle* out_loader);

    [DllImport("ke_asset_assimp", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_asset_assimp_set_log_callback", ExactSpelling = true)]
    public static extern void asset_assimp_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, KernelEngine.Logger.Native.ke_log_level, sbyte*, sbyte*, void> callback, void* ctx);
}
