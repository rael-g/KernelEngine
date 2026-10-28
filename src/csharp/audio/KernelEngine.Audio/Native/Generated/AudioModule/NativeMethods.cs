using System.Runtime.InteropServices;

using KernelEngine.Framework.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Audio.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_audio_module", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_audio_scene_components_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.ke_result audio_scene_components_create([NativeTypeName("ke_scene_component_set *")] KernelEngine.Framework.Native.ke_scene_component_set* set);

    [DllImport("ke_audio_module", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_audio_module_set_log_callback", ExactSpelling = true)]
    public static extern void audio_module_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, KernelEngine.Logger.Native.ke_log_level, sbyte*, sbyte*, void> callback, void* ctx);
}
