namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_audio
{
    public void* handle;

    [NativeTypeName("void (*)(struct ke_audio *)")]
    public delegate* unmanaged[Cdecl]<ke_audio*, void> destroy;

    [NativeTypeName("ke_result (*)(struct ke_audio *, const char *, ke_audio_sound *)")]
    public delegate* unmanaged[Cdecl]<ke_audio*, sbyte*, uint*, int> load_sound;

    [NativeTypeName("void (*)(struct ke_audio *, ke_audio_sound)")]
    public delegate* unmanaged[Cdecl]<ke_audio*, uint, void> unload_sound;

    [NativeTypeName("ke_result (*)(struct ke_audio *, ke_audio_sound, float, bool)")]
    public delegate* unmanaged[Cdecl]<ke_audio*, uint, float, bool, int> play;

    [NativeTypeName("void (*)(struct ke_audio *, ke_audio_sound)")]
    public delegate* unmanaged[Cdecl]<ke_audio*, uint, void> stop;

    [NativeTypeName("void (*)(struct ke_audio *, float)")]
    public delegate* unmanaged[Cdecl]<ke_audio*, float, void> set_master_volume;
}
