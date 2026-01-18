# Performance Tuning

The container comes pre-configured with optimized JVM settings. For most users, you only need to adjust memory allocation.

## Memory Allocation

### Recommended Settings by Player Count

| Players | INIT_MEMORY | MAX_MEMORY |
|---------|-------------|------------|
| 1-10    | 4G          | 4G         |
| 10-20   | 6G          | 6G         |
| 20-50   | 8G          | 8G         |
| 50+     | 12G         | 12G        |

### Configuration
```yaml
environment:
  - INIT_MEMORY=8G
  - MAX_MEMORY=8G
```

**Why set them equal?** Prevents heap resizing during operation which can cause lag spikes.

## Advanced Tuning

### Custom JVM Flags

If you need custom JVM flags, use `JVM_OPTS` for general options or `JVM_XX_OPTS` for `-XX:` options:

```yaml
environment:
  - JVM_OPTS=-Dcustom.property=value
  - JVM_XX_OPTS=-XX:MaxGCPauseMillis=100
```

**Note:** `JVM_XX_OPTS` are prepended to the base options, while `JVM_OPTS` are appended. This allows you to override defaults when needed.

### Pre-configured Optimizations

The container already includes these G1GC optimizations:

- `-XX:+UseG1GC` - G1 garbage collector
- `-XX:MaxGCPauseMillis=200` - Target max GC pause time
- `-XX:+UnlockExperimentalVMOptions` - Enable experimental features
- `-XX:+DisableExplicitGC` - Disable System.gc() calls
- `-XX:+UseStringDeduplication` - Deduplicate strings in heap
- `-XX:G1NewSizePercent=30` - Minimum young generation size
- `-XX:G1MaxNewSizePercent=40` - Maximum young generation size
- `-XX:G1HeapRegionSize=32M` - G1 heap region size
- `-XX:G1ReservePercent=20` - Reserve heap percentage
- `-XX:InitiatingHeapOccupancyPercent=15` - GC trigger threshold
- `-Dfile.encoding=UTF-8` - File encoding
- `--enable-native-access=ALL-UNNAMED` - Native library access

These settings are optimized for server workloads and provide a good balance between throughput and latency.

### Monitoring

Check JVM performance from your host:

```bash
# GC statistics (every second, 10 samples)
docker compose exec hytale jstat -gc 1 1000 10

# Container resource usage (CPU, memory, network)
docker stats hytale

# View JVM options in use
docker compose exec hytale ps aux | grep java
```

**Note:** The `jstat` command requires the Java process PID. Use `ps aux | grep java` inside the container to find it, or monitor the main process (PID 1).

## Performance Tips

1. **Allocate enough RAM** - Undersizing causes frequent garbage collection and lag spikes
2. **Don't over-allocate** - Leave headroom for the OS (at least 2GB recommended)
3. **SSD storage** - Significantly improves world loading and chunk generation
4. **Network** - Ensure stable connection for multiplayer; consider QoS settings
5. **Monitor GC pauses** - Use `jstat` to verify GC pause times stay under 200ms
6. **View radius** - Lower `MAX_VIEW_RADIUS` reduces memory usage and improves performance

## Troubleshooting

### High Memory Usage

If the server uses all allocated memory:
- Increase `MAX_MEMORY` if you have available RAM
- Reduce `MAX_VIEW_RADIUS` to decrease chunk loading
- Lower `MAX_PLAYERS` if experiencing issues

### GC Pauses Causing Lag

If experiencing lag spikes:
- Verify GC pause times with `jstat`
- Consider increasing `MAX_MEMORY` to reduce GC frequency
- Adjust `-XX:MaxGCPauseMillis` via `JVM_XX_OPTS` if needed (default: 200ms)

### Container Resource Limits

You can set Docker resource limits in `docker-compose.yml`:

```yaml
services:
  hytale:
    deploy:
      resources:
        limits:
          memory: 16G
          cpus: '4'
        reservations:
          memory: 8G
          cpus: '2'
```

This prevents the container from consuming all available system resources.

