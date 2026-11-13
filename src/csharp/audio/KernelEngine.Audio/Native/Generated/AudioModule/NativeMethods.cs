using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;

using KernelEngine.Ecs.Native;
using KernelEngine.Module.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Audio.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_audio_module", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_audio_module_set_log_callback", ExactSpelling = true)]
    public static extern void audio_module_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);

    [DllImport("ke_audio_module", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_sound_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result sound_create([NativeTypeName("ke_ecs *")] KernelEngine.Ecs.Native.ke_ecs* ecs, ke_audio* audio, [NativeTypeName("const ke_sound_config *")] ke_sound_config* config, [NativeTypeName("ke_module_handle *")] KernelEngine.Module.Native.ke_module_handle* out_module);
}
