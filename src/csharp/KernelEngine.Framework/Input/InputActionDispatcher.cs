using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Per-frame evaluation of every registered <see cref="InputActionMap{TEnum}"/> against the current
/// input snapshot. Updates each action's <c>Curr/Prev</c> values and emits
/// <see cref="InputActionEvent"/>s for phase transitions (Started / Performed / Canceled).
/// </summary>
/// <remarks>
/// <para>
/// Runs on ke.sim once per frame, between input-event dispatch and node Update. Polling readers
/// see the updated values when game code asks for them in the same frame; event handlers fire via
/// <see cref="Tree.DispatchActionEvents"/>.
/// </para>
/// <para>
/// Combination rule for multiple bindings on the same action (spec §5): max-magnitude per component.
/// A held Key.W + a stick at (0.3, 0.6) on the same Move action collapses to (1, 1) on the Y axis,
/// not (1.6) — this matches Unity Input System and avoids surprise saturation.
/// </para>
/// </remarks>
internal sealed class InputActionDispatcher
{
    private readonly List<InputActionEvent> _pending = new(32);

    /// <summary>
    /// Re-samples every registered map's bindings, updates action state, and produces the list of
    /// action events for the Tree to dispatch this frame.
    /// </summary>
    public List<InputActionEvent> Evaluate(IInputReader reader)
    {
        _pending.Clear();
        foreach (var map in InputActions.AllMaps)
        {
            var enumType = map.EnumType;
            foreach (var action in map.Actions)
            {
                // Roll: prev = curr; recompute curr from bindings.
                action.PrevX = action.CurrX;
                action.PrevY = action.CurrY;
                action.PrevZ = action.CurrZ;

                float cx = 0f, cy = 0f, cz = 0f;
                foreach (var binding in action.Bindings)
                {
                    binding.Sample(reader, out var bx, out var by, out var bz);
                    // Max-magnitude per component (preserves sign).
                    if (MathF.Abs(bx) > MathF.Abs(cx)) cx = bx;
                    if (MathF.Abs(by) > MathF.Abs(cy)) cy = by;
                    if (MathF.Abs(bz) > MathF.Abs(cz)) cz = bz;
                }
                action.CurrX = cx;
                action.CurrY = cy;
                action.CurrZ = cz;

                EmitPhaseEvent(enumType, action);
            }
        }
        return _pending;
    }

    private void EmitPhaseEvent(Type enumType, InputAction action)
    {
        bool nowActive  = action.IsActiveNow;
        bool prevActive = action.WasActivePrev;

        ActionPhase? phase = (prevActive, nowActive) switch
        {
            (false, true) => ActionPhase.Started,
            (true,  true) when ValueChanged(action) && action.Type != ActionType.Button => ActionPhase.Performed,
            (true,  false) => ActionPhase.Canceled,
            _ => null,
        };

        if (phase is null) return;

        _pending.Add(new InputActionEvent
        {
            EnumType = enumType,
            ActionId = action.ActionId,
            Type     = action.Type,
            Phase    = phase.Value,
            ValueX   = action.CurrX,
            ValueY   = action.CurrY,
            ValueZ   = action.CurrZ,
        });
    }

    private static bool ValueChanged(InputAction a) =>
        a.PrevX != a.CurrX || a.PrevY != a.CurrY || a.PrevZ != a.CurrZ;
}
