using KernelEngine.Common.Native;
using System.Runtime.CompilerServices;

namespace KernelEngine.Audio.Native;

public partial struct ke_audio_player_component
{
    [NativeTypeName("char[256]")]
    public _path_e__FixedBuffer path;

    public float volume;

    [InlineArray(256)]
    public partial struct _path_e__FixedBuffer
    {
        public sbyte e0;
    }
}
