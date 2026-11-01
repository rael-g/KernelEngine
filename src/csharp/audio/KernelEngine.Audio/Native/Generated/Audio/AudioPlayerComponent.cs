using System.Numerics;
using System.Runtime.CompilerServices;

using KernelEngine.Result.Native;

namespace KernelEngine.Audio.Native;

public partial struct AudioPlayerComponent
{
    [NativeTypeName("char[256]")]
    public _Path_e__FixedBuffer Path;

    public float Volume;

    [InlineArray(256)]
    public partial struct _Path_e__FixedBuffer
    {
        public sbyte e0;
    }
}
