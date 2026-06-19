using KernelEngine.Common.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Audio.MiniAudio.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_audio_miniaudio", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_audio_miniaudio_create", ExactSpelling = true)]
    public static extern ke_result audio_miniaudio_create([NativeTypeName("const ke_audio_miniaudio_params *")] ke_audio_miniaudio_params* @params, [NativeTypeName("ke_audio_handle *")] KernelEngine.Audio.Native.ke_audio_handle* @out, ke_error** out_error);
}
