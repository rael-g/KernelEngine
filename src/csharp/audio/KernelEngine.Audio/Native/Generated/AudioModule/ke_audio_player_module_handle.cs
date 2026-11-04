using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;

using KernelEngine.Ecs.Native;
using KernelEngine.Framework.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;

namespace KernelEngine.Audio.Native;

public unsafe partial struct ke_audio_player_module_handle
{
    public ke_audio_player_module* @ref;

    [NativeTypeName("void (*)(ke_audio_player_module *)")]
    public delegate* unmanaged[Cdecl]<ke_audio_player_module*, void> destroy;
}
