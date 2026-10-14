# 0003. A plugin sees only the domains it asked for

Recorded: 2026-10-13. The decision is older than this record.

## Context
Contracts live in one directory per domain. A meta-target or umbrella header would give every plugin
every contract.

## Decision
The root build gives each plugin one include directory per domain it consumes, as a `-D` option.
There is no umbrella header.

## Consequences
A dependency on a domain is visible in the plugin's `build.zig`, and including a header of a domain
not asked for fails to compile.
