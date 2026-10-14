# 0009. Commands reach the GPU in command-slot order, chosen by each pass

Recorded: 2026-10-13. The decision is older than this record.

## Context
The runtime runs systems in waves placed greedily in registration order; a conflict only pushes a
system later. Access lists therefore cannot guarantee that a writer's commands are submitted before
a reader's.

## Decision
Each pass records into the command slot named in its `ke_render_pass_io`. At the end of the frame
the service walks the slots in ascending order, finishes each recorded one and submits them in one
call. The slot numbers are literals in each pass plugin, not declared by a contract.

## Consequences
- What is submitted is ordered by slot whatever order the bodies ran in.
- A pass added by a host must pick a slot consistent with the existing ones, by reading the code.
- The number of slots the service keeps is a fixed capacity.
