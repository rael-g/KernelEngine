using KernelEngine.Asset.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Input.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Framework.Native;

[NativeTypeName("unsigned int")]
public enum ke_script_borrow : uint
{
    KE_SCRIPT_BORROW_DESCENDANT = 0,
    KE_SCRIPT_BORROW_ANCESTOR = 1,
    KE_SCRIPT_BORROW_ANYWHERE = 2,
}
