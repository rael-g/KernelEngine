using KernelEngine.Kernel.Native;

namespace KernelEngine.Audio.MiniAudio.Native;

public unsafe partial struct ke_audio_miniaudio_params
{
    [NativeTypeName("struct ke_logger *")]
    public KernelEngine.Kernel.Native.ke_logger* logger;
}
