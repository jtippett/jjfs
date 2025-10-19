# FUSE Implementation Approach

## Decision for V1

Use `bindfs` as external dependency for pass-through mounting:
- Mature, well-tested
- Simple integration via Process.run
- Allows focus on sync logic

## Future V2

Implement native FUSE via FFI for:
- Better error handling
- Custom optimizations
- Reduced external dependencies
