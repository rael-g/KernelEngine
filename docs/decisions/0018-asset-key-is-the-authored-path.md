# 0018. A cached asset is identified by the key alone, and the key is the path as authored

Recorded: 2026-10-13. The decision is older than this record.

## Context
The same texture can be requested as "res://a.png", as an absolute path, or by two systems at
once. The render service must not decode or upload it twice.

## Decision
The `resolve_*_into` slots use the authored path as the key for `try_get_*` and for the upload;
the service's `ke_resource_cache` returns the cached handle on a hit and compares no other
argument.

## Consequences
- "res://a.png" and the absolute path of that file are two textures.
- A second `create_material` under an existing key with different values returns the first
  material.
- Every cache hit retains for the caller and owes one `release`.
- The cache keeps the key text, so two keys with equal hashes remain two entries.
