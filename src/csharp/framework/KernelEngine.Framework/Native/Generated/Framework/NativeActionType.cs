using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Input;
using global::KernelEngine.Logger;

using KernelEngine.Asset.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Input.Native;
using KernelEngine.Io.Native;
using KernelEngine.Part.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Schedule.Native;
using KernelEngine.Settings.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Framework.Native;

[NativeTypeName("unsigned int")]
public enum NativeActionType : uint
{
    Button = 0,
    Axis1D = 1,
    Axis2D = 2,
    Axis3D = 3,
}
