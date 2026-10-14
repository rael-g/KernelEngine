# 0010. A pass is never made to wait for a pipeline compile

Recorded: 2026-10-13. The decision is older than this record.

## Context
Compiling a render pipeline can take long enough to stall a frame. Passes ask for a pipeline each
time they draw and run inside the frame.

## Decision
`get_or_create_pipeline` returns at once. The first request builds a placeholder pipeline whose
fragment shader writes magenta and starts the real compile on the device asynchronously; later
requests return the real pipeline once it has been delivered. A compile that fails leaves the
placeholder.

## Consequences
- Magenta on screen means a request that has not resolved yet.
- The cache must outlive every compile that may still call back, so the service flushes the device's
  compiles before it destroys the cache.
- When an allocation fails the pipeline is created synchronously and not cached.
