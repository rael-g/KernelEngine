using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;

using KernelEngine.Configuration.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;

namespace KernelEngine.Audio.Native;

public unsafe partial struct ke_sound_module_handle
{
    public ke_sound_module* @ref;

    [NativeTypeName("void (*)(ke_sound_module *)")]
    public delegate* unmanaged[Cdecl]<ke_sound_module*, void> destroy;
}
