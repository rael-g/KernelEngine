using System.Numerics;
using System.Runtime.CompilerServices;

using global::KernelEngine.Ecs;
using global::KernelEngine.Input;
using global::KernelEngine.Logger;

using KernelEngine.Asset.Native;
using KernelEngine.Configuration.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Io.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Framework.Native;

public partial struct NameComponent
{
    [NativeTypeName("char[64]")]
    public _Name_e__FixedBuffer Name;

    [InlineArray(64)]
    public partial struct _Name_e__FixedBuffer
    {
        public sbyte e0;
    }
}
