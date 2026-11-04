using System.Numerics;
using System.Runtime.CompilerServices;

using KernelEngine.Result.Native;

namespace KernelEngine.Audio.Native;

public partial struct SoundComponent
{
    [NativeTypeName("char[256]")]
    public _Path_e__FixedBuffer Path;

    public float Volume;

    public float Pitch;

    public bool Loop;

    public bool Playing;

    [NativeTypeName("ke_sound_release")]
    public SoundRelease Release;

    [NativeTypeName("ke_audio_sound")]
    public uint Clip;

    [NativeTypeName("ke_audio_voice")]
    public uint Voice;

    [InlineArray(256)]
    public partial struct _Path_e__FixedBuffer
    {
        public sbyte e0;
    }
}
