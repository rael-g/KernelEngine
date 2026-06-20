using KernelEngine.Common.Native;

namespace KernelEngine.Audio.Native;

public unsafe partial struct ke_audio
{
    public void* handle;

    [NativeTypeName("ke_audio_sound (*)(struct ke_audio *, const char *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_audio*, sbyte*, ke_error**, uint> load_sound;

    [NativeTypeName("void (*)(struct ke_audio *, ke_audio_sound)")]
    public delegate* unmanaged[Cdecl]<ke_audio*, uint, void> unload_sound;

    [NativeTypeName("bool (*)(struct ke_audio *, ke_audio_sound, float, ke_bool, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_audio*, uint, float, byte, ke_error**, bool> play;

    [NativeTypeName("void (*)(struct ke_audio *, ke_audio_sound)")]
    public delegate* unmanaged[Cdecl]<ke_audio*, uint, void> stop;

    [NativeTypeName("void (*)(struct ke_audio *, float)")]
    public delegate* unmanaged[Cdecl]<ke_audio*, float, void> set_master_volume;
}
