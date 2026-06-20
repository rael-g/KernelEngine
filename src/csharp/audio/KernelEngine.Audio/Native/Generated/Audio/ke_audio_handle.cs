using KernelEngine.Common.Native;

namespace KernelEngine.Audio.Native;

public unsafe partial struct ke_audio_handle
{
    public ke_audio* @ref;

    [NativeTypeName("void (*)(ke_audio *)")]
    public delegate* unmanaged[Cdecl]<ke_audio*, void> destroy;
}
