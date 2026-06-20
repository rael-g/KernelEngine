using KernelEngine.Common.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Audio.MiniAudio.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_audio_miniaudio", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_audio_miniaudio_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_audio_handle")]
    public static extern KernelEngine.Audio.Native.ke_audio_handle audio_miniaudio_create([NativeTypeName("const ke_audio_miniaudio_params *")] ke_audio_miniaudio_params* @params, ke_error** out_error);
}
