using System.Numerics;

using global::KernelEngine.Logger;

using KernelEngine.Result.Native;

namespace KernelEngine.Configuration.Native;

[NativeTypeName("unsigned int")]
public enum ConfigType : uint
{
    Int,
    Float,
    Double,
    Bool,
    String,
}
