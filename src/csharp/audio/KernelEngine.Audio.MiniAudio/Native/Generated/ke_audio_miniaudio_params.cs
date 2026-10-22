using KernelEngine.Audio.Native;
using KernelEngine.Common.Native;
using KernelEngine.Logger.Native;

namespace KernelEngine.Audio.MiniAudio.Native;

public unsafe partial struct ke_audio_miniaudio_params
{
    [NativeTypeName("struct ke_logger *")]
    public KernelEngine.Logger.Native.ke_logger* logger;
}
