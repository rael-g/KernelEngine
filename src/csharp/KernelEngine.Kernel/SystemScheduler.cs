using System.Collections.Generic;
using System.Linq;

namespace KernelEngine.Kernel;

/// <summary>
/// Partitions a list of systems into execution waves based on their component access.
/// </summary>
internal sealed class SystemScheduler
{
    private SystemWave[] _waves = [];

    public void Build(IReadOnlyList<ISystem> systems)
    {
        var waves = new List<SystemWave>();
        var currentWaveSystems = new List<ISystem>();

        foreach (var system in systems)
        {
            var access = system.GetAccess();

            // If the system is a serial barrier (Access.None) or conflicts with current wave
            if (access.Reads.Count == 0 && access.Writes.Count == 0 || Conflicts(currentWaveSystems, access))
            {
                // Close current wave if not empty
                if (currentWaveSystems.Count > 0)
                {
                    waves.Add(new SystemWave { Systems = [.. currentWaveSystems], Parallel = currentWaveSystems.Count > 1 });
                    currentWaveSystems.Clear();
                }

                // If it's a serial barrier, it must run in its own wave
                if (access.Reads.Count == 0 && access.Writes.Count == 0)
                {
                    waves.Add(new SystemWave { Systems = [system], Parallel = false });
                    continue;
                }
            }

            currentWaveSystems.Add(system);
        }

        if (currentWaveSystems.Count > 0)
        {
            waves.Add(new SystemWave { Systems = [.. currentWaveSystems], Parallel = currentWaveSystems.Count > 1 });
        }

        _waves = [.. waves];
    }

    public async Task RunAsync(World world, float dt, FramePacket? packet, TaskScheduler taskScheduler, IInputReader? input = null)
    {
        foreach (var wave in _waves)
        {
            if (!wave.Parallel)
            {
                // Serial execution: run directly on the sim thread
                Input.SetCurrentReader(input);
                try
                {
                    foreach (var system in wave.Systems)
                    {
                        system.Update(world, dt, packet, input);
                    }
                }
                finally
                {
                    Input.SetCurrentReader(null);
                }
            }
            else if (taskScheduler != null)
            {
                // Parallel execution: dispatch all systems in the wave to the task pool
                var tasks = new Task[wave.Systems.Length];
                for (int i = 0; i < wave.Systems.Length; i++)
                {
                    var sys = wave.Systems[i];
                    tasks[i] = taskScheduler.Dispatch(() =>
                    {
                        Input.SetCurrentReader(input);
                        try
                        {
                            sys.Update(world, dt, packet, input);
                        }
                        finally
                        {
                            Input.SetCurrentReader(null);
                        }
                    });
                }

                // Wait for all systems in this wave to finish before starting the next wave
                await Task.WhenAll(tasks);
            }
            else
            {
                // No task scheduler — fall back to sequential
                Input.SetCurrentReader(input);
                try
                {
                    foreach (var system in wave.Systems)
                        system.Update(world, dt, packet, input);
                }
                finally
                {
                    Input.SetCurrentReader(null);
                }
            }
        }
    }

    private static bool Conflicts(List<ISystem> wave, ComponentAccess newAccess)
    {
        foreach (var system in wave)
        {
            var existing = system.GetAccess();

            // Write-Write conflict
            if (existing.Writes.Any(id => newAccess.Writes.Contains(id))) return true;
            
            // Write-Read conflict
            if (existing.Writes.Any(id => newAccess.Reads.Contains(id))) return true;
            if (newAccess.Writes.Any(id => existing.Reads.Contains(id))) return true;
        }
        return false;
    }
}

internal sealed class SystemWave
{
    public ISystem[] Systems { get; init; } = [];
    public bool Parallel { get; init; }
}
