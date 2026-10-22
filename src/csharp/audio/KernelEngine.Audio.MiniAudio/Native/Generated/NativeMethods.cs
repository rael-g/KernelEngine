using System.Runtime.InteropServices;

using KernelEngine.Audio.Native;
using KernelEngine.Common.Native;
using KernelEngine.Logger.Native;

namespace KernelEngine.Audio.MiniAudio.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_audio_miniaudio", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_audio_miniaudio_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_audio_handle")]
    public static extern KernelEngine.Audio.Native.ke_audio_handle audio_miniaudio_create([NativeTypeName("ke_error **")] KernelEngine.Common.Native.ke_error** out_error);

    [DllImport("ke_audio_miniaudio", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_audio_miniaudio_set_log_callback", ExactSpelling = true)]
    public static extern void audio_miniaudio_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, KernelEngine.Logger.Native.ke_log_level, sbyte*, sbyte*, void> callback, void* ctx);
}
