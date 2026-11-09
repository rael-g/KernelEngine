using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Input;
using global::KernelEngine.Logger;

using KernelEngine.Asset.Native;
using KernelEngine.Configuration.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Input.Native;
using KernelEngine.Io.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Framework.Native;

[NativeTypeName("unsigned int")]
public enum ScriptReach : uint
{
    Self = 0,
    Any = 1,
}
