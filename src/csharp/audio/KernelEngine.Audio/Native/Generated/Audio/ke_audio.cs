using System.Numerics;

using KernelEngine.Result.Native;

namespace KernelEngine.Audio.Native;

public unsafe partial struct ke_audio
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_audio *, const char *, ke_audio_sound *)")]
    public delegate* unmanaged[Cdecl]<ke_audio*, sbyte*, uint*, KernelEngine.Result.Native.Result> load_sound;

    [NativeTypeName("void (*)(struct ke_audio *, ke_audio_sound)")]
    public delegate* unmanaged[Cdecl]<ke_audio*, uint, void> unload_sound;

    [NativeTypeName("ke_result (*)(struct ke_audio *, ke_audio_sound, float, float, bool, ke_audio_voice *)")]
    public delegate* unmanaged[Cdecl]<ke_audio*, uint, float, float, bool, uint*, KernelEngine.Result.Native.Result> voice_start;

    [NativeTypeName("bool (*)(struct ke_audio *, ke_audio_voice)")]
    public delegate* unmanaged[Cdecl]<ke_audio*, uint, bool> voice_playing;

    [NativeTypeName("void (*)(struct ke_audio *, ke_audio_voice)")]
    public delegate* unmanaged[Cdecl]<ke_audio*, uint, void> voice_stop;

    [NativeTypeName("void (*)(struct ke_audio *, float)")]
    public delegate* unmanaged[Cdecl]<ke_audio*, float, void> set_master_volume;
}
