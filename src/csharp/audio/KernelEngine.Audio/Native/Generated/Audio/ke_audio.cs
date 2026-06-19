using KernelEngine.Common.Native;

namespace KernelEngine.Audio.Native;

public unsafe partial struct ke_audio
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_audio *, const char *, ke_audio_sound *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_audio*, sbyte*, uint*, ke_error**, ke_result> load_sound;

    [NativeTypeName("void (*)(struct ke_audio *, ke_audio_sound)")]
    public delegate* unmanaged[Cdecl]<ke_audio*, uint, void> unload_sound;

    [NativeTypeName("ke_result (*)(struct ke_audio *, ke_audio_sound, float, ke_bool, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_audio*, uint, float, byte, ke_error**, ke_result> play;

    [NativeTypeName("void (*)(struct ke_audio *, ke_audio_sound)")]
    public delegate* unmanaged[Cdecl]<ke_audio*, uint, void> stop;

    [NativeTypeName("void (*)(struct ke_audio *, float)")]
    public delegate* unmanaged[Cdecl]<ke_audio*, float, void> set_master_volume;
}
