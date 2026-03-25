# Recipe Resolution Performance Observations

## Context

These are informal notes from profiling recipe resolution under various conditions.
Not an issue, not a feature request — constraint characterization for planning purposes.

## Observed Timings (local filesystem, no network)

| Operation | Typical | Worst case |
|-----------|---------|-----------|
| Single recipe lookup | 2-5ms | 15ms (cold cache) |
| Full registry scan (450 recipes) | 180ms | 340ms |
| Version resolution (GitHub API) | 400-900ms | 3s (rate limited) |
| Recipe validation | <1ms | 5ms (large recipe) |

## Bottlenecks

1. **GitHub API calls dominate**: version resolution for github provider makes
   one API call per recipe. Parallel resolution (current) helps but rate limits
   apply at 60 req/min unauthenticated.

2. **Registry scan is linear**: `tsuku list` scans all recipes to build the
   installed set. At 450 recipes this is ~180ms; at 2000 recipes it would be ~800ms.

3. **No caching of resolved versions**: each invocation re-resolves from the provider.
   A 1-hour TTL cache would eliminate most GitHub API calls.

## Notes

These numbers are from a development machine (NVMe SSD, 32GB RAM). Network-bound
environments (CI with throttled egress) see version resolution climb to 2-4s per recipe.
