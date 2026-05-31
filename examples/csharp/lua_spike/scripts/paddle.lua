-- paddle.lua
-- Minimal Lua script wired to ke_script_component for the Tier S spike.
-- The C ScriptSystem calls on_awake → on_start → on_update each frame.
-- entity is a uint64 passed by value; dt is a float.

local speed = 5.0
local total_time = 0.0

function on_awake(entity)
    print(string.format("[lua] on_awake  entity=%d", entity))
end

function on_start(entity)
    print(string.format("[lua] on_start  entity=%d  speed=%.1f", entity, speed))
end

function on_update(entity, dt)
    total_time = total_time + dt
    -- Simulate paddle velocity update (no actual ECS write here — spike only).
    local velocity = speed * dt
    print(string.format("[lua] on_update entity=%d  dt=%.4f  velocity=%.4f  total=%.4f",
        entity, dt, velocity, total_time))
end

function on_late_update(entity, dt)
    -- Runs after all on_update calls in the same frame.
    print(string.format("[lua] on_late_update entity=%d", entity))
end

function on_destroy(entity)
    print(string.format("[lua] on_destroy entity=%d", entity))
end
