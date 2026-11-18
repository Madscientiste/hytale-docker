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

**Equal or not?** Equal values stop the heap from resizing while the server runs, which can prevent lag spikes. The table uses equal values. The `docker-compose.yml` defaults are `INIT_MEMORY=8G` and `MAX_MEMORY=16G`: the heap starts at 8G and can grow to 16G.

## Advanced Tuning

### Custom JVM Flags

Put custom JVM flags in `JVM_OPTS`. They come after the image's own options, and Java uses the last value of an option, so `JVM_OPTS` can also change a default:

```yaml
environment:
  - JVM_OPTS=-XX:MaxGCPauseMillis=100 -Dcustom.property=value
```

`JVM_XX_OPTS` comes before the image's options, so it cannot change a default: the image's value comes later and wins. Use it only for `-XX:` options the image does not set.

The image is tuned for the G1 garbage collector (`-XX:+UseG1GC`). Adding another collector, such as `-XX:+UseZGC`, stops Java with "Multiple garbage collectors selected".

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

### AOT Cache (faster startup)

Some Hytale downloads include `HytaleServer.aot` next to the server jar: an ahead-of-time cache (JEP 514) that makes the server start faster. When a download has one, the container keeps it in `/data` and adds `-XX:AOTCache=HytaleServer.aot`. Without the file (the 0.7.7 release has none), the server starts normally.

The cache only works with the exact jar and Java version it was built for. If they don't match, Java prints a warning and starts normally without it.

### Monitoring

Check performance from your host:

```bash
# Container resource usage (CPU, memory, network)
docker stats hytale

# View JVM options in use
docker compose exec hytale ps aux | grep java
```

The image has a Java runtime only, so JDK tools such as `jstat` are not in it. To see garbage collection pauses, write a GC log with `JVM_OPTS`:

```yaml
environment:
  - JVM_OPTS=-Xlog:gc*:file=/data/gc.log:time,uptime:filecount=5,filesize=10m
```

The log is `data/gc.log` on the host. Each pause line shows how long the pause took.

## Performance Tips

1. **Allocate enough RAM** - Undersizing causes frequent garbage collection and lag spikes
2. **Don't over-allocate** - Leave headroom for the OS (at least 2GB recommended)
3. **SSD storage** - Significantly improves world loading and chunk generation
4. **Network** - Ensure stable connection for multiplayer; consider QoS settings
5. **Monitor GC pauses** - Use a GC log (see [Monitoring](#monitoring)) to verify GC pause times stay under 200ms
6. **View radius** - Lower `MAX_VIEW_RADIUS` reduces memory usage and improves performance

## Troubleshooting

### High Memory Usage

If the server uses all allocated memory:
- Increase `MAX_MEMORY` if you have available RAM
- Reduce `MAX_VIEW_RADIUS` to decrease chunk loading
- Lower `MAX_PLAYERS` if experiencing issues

### GC Pauses Causing Lag

If experiencing lag spikes:
- Verify GC pause times with a GC log (see [Monitoring](#monitoring))
- Consider increasing `MAX_MEMORY` to reduce GC frequency
- Adjust `-XX:MaxGCPauseMillis` via `JVM_OPTS` if needed (default: 200ms)

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

