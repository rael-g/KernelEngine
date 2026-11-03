using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;

using KernelEngine.Framework.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Audio.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_audio_module", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_audio_scene_components_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result audio_scene_components_create([NativeTypeName("ke_scene_component_set *")] KernelEngine.Framework.Native.ke_scene_component_set* set);

    [DllImport("ke_audio_module", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_audio_module_set_log_callback", ExactSpelling = true)]
    public static extern void audio_module_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
