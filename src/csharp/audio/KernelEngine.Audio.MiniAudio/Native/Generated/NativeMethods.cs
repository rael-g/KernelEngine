using KernelEngine.Kernel.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Audio.MiniAudio.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_audio_miniaudio", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_audio_miniaudio_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Kernel.Native.ke_result audio_miniaudio_create([NativeTypeName("const ke_audio_miniaudio_params *")] ke_audio_miniaudio_params* @params, [NativeTypeName("ke_audio **")] KernelEngine.Kernel.Native.ke_audio** @out, ke_error** out_error);
}
