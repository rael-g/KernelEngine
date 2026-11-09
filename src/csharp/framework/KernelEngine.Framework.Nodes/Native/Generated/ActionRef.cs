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

public partial struct ActionRef
{
    [NativeTypeName("char[32]")]
    public _Name_e__FixedBuffer Name;

    [NativeTypeName("int32_t")]
    public int Id;

    public bool Resolved;

    [InlineArray(32)]
    public partial struct _Name_e__FixedBuffer
    {
        public sbyte e0;
    }
}
