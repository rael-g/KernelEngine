using System.Numerics;
using System.Runtime.CompilerServices;

using global::KernelEngine.Common;
using global::KernelEngine.Ecs;
using global::KernelEngine.Physics;
using global::KernelEngine.Render;

using KernelEngine.Asset.Native;
using KernelEngine.Audio.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Framework.Native;
using KernelEngine.Io.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;

namespace KernelEngine.Framework.Nodes.Native;

public partial struct SceneSlotComponent
{
    [NativeTypeName("char[256]")]
    public _PathBytes_e__FixedBuffer PathBytes;

    [NativeTypeName("char[256]")]
    public _LoadedBytes_e__FixedBuffer LoadedBytes;

    [InlineArray(256)]
    public partial struct _PathBytes_e__FixedBuffer
    {
        public sbyte e0;
    }

    [InlineArray(256)]
    public partial struct _LoadedBytes_e__FixedBuffer
    {
        public sbyte e0;
    }
}
