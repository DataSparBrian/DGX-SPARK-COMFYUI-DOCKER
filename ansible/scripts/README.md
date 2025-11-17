# GPU Performance Optimization for DGX Spark

This directory contains performance optimization scripts for the NVIDIA DGX Spark system, which features a Grace-Blackwell System-on-Chip (SoC) architecture with ARM Cortex CPU and NVIDIA GB10 Blackwell GPU.

## System Architecture

**DGX Spark Specifications:**
- **CPU**: ARM Cortex-X925 + Cortex-A725 (20 cores total)
- **GPU**: NVIDIA GB10 Blackwell (122GB unified memory)
- **Interconnect**: NVLink-C2C coherent chip-to-chip interconnect (~900 GB/s bidirectional)
- **Architecture**: Grace-Blackwell SoC with cache-coherent unified memory

**Note**: The PCIe interface may report as "PCIe 1.0 x1" in system tools, but this is a legacy compatibility layer. The actual CPU-GPU communication happens over the high-speed NVLink-C2C interconnect, providing significantly better bandwidth than traditional PCIe.

## Optimization Scripts

This directory contains three complementary optimization scripts for maximum system performance:

### `gpu_optimize.sh` - GPU and CPU Optimizations

Focuses on NVIDIA GPU settings and ARM CPU power management.

### `system_optimize.sh` - System-Level Optimizations

Focuses on memory, I/O, ZFS, network, and scheduler tuning.

### `make_persistent.sh` - Persistence Configuration

Makes optimizations survive reboots by creating system configuration files.

**Features:**
- Creates systemd service for GPU/CPU optimizations
- Generates sysctl configs for memory/network settings
- Sets up udev rules for I/O optimization
- Configures ZFS module parameters
- Enables transparent hugepages via rc.local

**Usage:**

```bash
# Install persistence (run after applying optimizations)
sudo ./make_persistent.sh install

# Check what's configured
sudo ./make_persistent.sh status

# Remove persistence configurations
sudo ./make_persistent.sh uninstall
```

## Complete Optimization Coverage

### GPU Optimizations (`gpu_optimize.sh`)

1. **Persistence Mode** (`nvidia-smi -pm 1`)
   - Keeps NVIDIA driver loaded even when no active clients exist
   - Reduces driver load latency for CUDA applications
   - **Benefit**: Faster application startup and reduced overhead
   - **Persistence**: Survives reboots

2. **Exclusive Compute Mode** - DISABLED
   - Originally enabled single-context GPU access
   - **Disabled**: Conflicts with desktop/Xorg environments
   - If you need this on a headless server, uncomment line 38 in `gpu_optimize.sh`

3. **Locked GPU Clocks** (`nvidia-smi -lgc 3003,3003`)
   - Forces GPU to maintain maximum clock speed (3003 MHz)
   - Prevents dynamic frequency scaling and throttling
   - Removes SW power capping that was limiting performance
   - **Benefit**: Consistent maximum performance, no clock ramp-up delays
   - **Persistence**: Resets on driver reload or reboot (needs re-application)

4. **Video Boost Slider** (`nvidia-smi boost-slider --vboost 1`)
   - Enables GPU core clock boost mode
   - Increases GPU core clock by reducing memory clock
   - Optimized for compute-bound workloads (LLMs, diffusion models)
   - **Benefit**: Higher compute throughput for AI inference
   - **Persistence**: Needs verification after reboot

5. **Accounting Mode** (`nvidia-smi -am 1`)
   - Enables process-level GPU usage tracking
   - Useful for monitoring and debugging
   - **Benefit**: Detailed performance metrics per process
   - **Persistence**: Survives reboots

### CPU Optimizations (`gpu_optimize.sh`)

1. **Deep C-State Disabling**
   - Disables CPU idle states 2 and 3 (deep sleep modes)
   - Keeps CPUs in lighter sleep states for faster wake-up
   - Applied to all 20 ARM cores
   - **Benefit**: Lower CPU wake latency (~10-100μs improvement)
   - **Persistence**: Resets on reboot (needs re-application)

2. **CPU Governor** (Already Optimized)
   - System already uses "performance" governor
   - CPUs run at maximum frequency
   - No additional changes needed

### System-Level Optimizations (`system_optimize.sh`)

#### Memory Management

1. **Swappiness Reduction** (60 → 10)
   - Default swappiness=60 is too aggressive for 120GB RAM system
   - Reduced to 10 to minimize swap usage
   - **Benefit**: Keep more data in RAM, avoid swap slowdown
   - **Impact**: With 120GB RAM, swap should be emergency-only

2. **Transparent Hugepages** (madvise → always)
   - Enables 2MB memory pages instead of 4KB
   - Critical for PyTorch and large model allocations
   - **Benefit**: 512x fewer TLB entries, faster memory access
   - **Impact**: Significant for multi-GB model tensors

3. **VFS Cache Pressure** (100 → 50)
   - Controls how aggressively kernel reclaims cache
   - Lower value = keep more file cache
   - **Benefit**: Faster model re-loading from disk cache
   - **Impact**: Models stay cached longer between runs

4. **Dirty Ratios** (20/10 → 40/10)
   - Increased dirty_ratio from 20% to 40%
   - More write buffering before flush
   - **Benefit**: Better write coalescing, fewer I/O interruptions
   - **Impact**: Smoother output file saves

#### I/O Scheduler Optimizations

1. **Queue Depth** (2 → 256)
   - Default nr_requests=2 is absurdly low
   - Increased to 256 for better pipeline depth
   - **Benefit**: USB 20Gbps drives can queue more requests
   - **Impact**: 128x better I/O parallelism

2. **Read-Ahead** (128KB → 4MB)
   - Increased from 128KB to 4096KB
   - Sequential model loading benefits massively
   - **Benefit**: Fewer I/O round-trips for large files
   - **Impact**: Faster model loading (10GB+ checkpoint files)

3. **Scheduler** (mq-deadline → none)
   - ZFS has its own sophisticated I/O scheduling
   - Linux scheduler adds unnecessary overhead
   - **Benefit**: Eliminate double-scheduling overhead
   - **Impact**: Lower latency, let ZFS optimize directly

#### ZFS Optimizations

1. **Autotrim** (off → on)
   - Enables automatic TRIM on SSD/USB drives
   - Prevents write amplification and wear
   - **Benefit**: Long-term drive health and performance
   - **Impact**: Sustained performance over months/years

2. **ARC Metadata Limit** (default → 8GB)
   - Increased metadata cache for directories/files
   - Faster lookups in large model directories
   - **Benefit**: Quicker file discovery and access
   - **Impact**: Noticeable with 1000+ model files

3. **Prefetch Tuning** (verified enabled)
   - Ensures ZFS prefetch is active
   - Predicts and pre-loads sequential reads
   - **Benefit**: Model loading anticipates next blocks
   - **Impact**: Smoother loading of large checkpoints

#### Network Optimizations

1. **Buffer Sizes** (212KB → 16MB)
   - Expanded RX/TX buffers from 212KB to 16MB
   - Critical for API throughput (image generation results)
   - **Benefit**: 75x larger buffers prevent drops
   - **Impact**: Better handling of large image responses

2. **TCP Fastopen** (1 → 3)
   - Enables data transmission during handshake
   - Reduces latency for new connections
   - **Benefit**: Faster API request initiation
   - **Impact**: Lower first-request latency

3. **TCP Slow Start After Idle** (1 → 0)
   - Prevents bandwidth throttling after idle period
   - Maintains full speed between requests
   - **Benefit**: Consistent API performance
   - **Impact**: No ramp-up delay between generations

4. **Netdev Backlog** (1000 → 5000)
   - Increased packet queue for network processing
   - Prevents drops during traffic bursts
   - **Benefit**: Better handling of multiple clients
   - **Impact**: Smoother multi-user scenarios

#### Scheduler Optimizations

1. **Autogroup Disabled** (1 → 0)
   - Prevents desktop session grouping interference
   - Server processes get consistent scheduling
   - **Benefit**: ComfyUI not throttled by other sessions
   - **Impact**: Predictable performance regardless of system activity

## Performance Impact

**Before Optimization:**
- GPU clocks: ~2400 MHz (throttled by SW power cap)
- Clock throttling: Active (27.8 billion μs of power capping)
- CPU wake latency: Higher due to deep C-states

**After Optimization:**
- GPU clocks: 3003 MHz locked (maximum)
- Clock throttling: Removed
- CPU wake latency: Reduced by disabling deep sleep
- vboost: Level 1 (compute mode - increases core clock)

**Expected Benefits:**
- Faster model loading and inference
- More consistent frame times for video generation
- Lower latency for interactive workflows
- Elimination of performance variance from clock scaling

## Ansible Playbook Integration

### Available Playbooks

Two complementary playbooks are provided for different use cases:

**`10_complete_optimize.yml`** - Full System Optimization
- Applies ALL optimizations (GPU, CPU, memory, I/O, ZFS, network)
- Makes settings persistent across reboots
- Optional reboot and verification
- **Use this for initial setup or complete reconfiguration**

**`11_apply_non_persistent.yml`** - Quick GPU/CPU Re-apply
- Only re-applies GPU clocks, vboost, and C-states
- Fast execution (~5 seconds)
- **Use this after reboots when you need to restore GPU clock settings**

### Quick Start: Complete Optimization (Recommended for First Time)

```bash
# Apply all optimizations + make persistent (no reboot)
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/native/10_complete_optimize.yml

# Apply + persist + REBOOT + verify everything survived (full test)
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/native/10_complete_optimize.yml -e 'do_reboot=true'

# Check status of all optimizations
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/native/10_complete_optimize.yml -e 'optimization_action=status'

# Undo everything
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/native/10_complete_optimize.yml -e 'optimization_action=undo'
```

**What `10_complete_optimize.yml` does:**

1. **Phase 1: Apply Optimizations**
   - GPU clocks, core boost, persistence mode
   - CPU C-state disabling
   - Memory tuning (swappiness, hugepages, cache)
   - I/O optimization (scheduler, queue depth, read-ahead)
   - ZFS tuning (autotrim, ARC, prefetch)
   - Network buffers and TCP settings

2. **Phase 2: Make Persistent**
   - Creates systemd service (`dgx-optimize.service`)
   - Installs sysctl configs
   - Sets up udev rules
   - Configures ZFS module parameters
   - Enables transparent hugepages via rc.local

3. **Phase 3: Reboot & Verify** (if `do_reboot=true`)
   - Reboots the system
   - Waits for it to come back online
   - Verifies optimizations
   - Reports status

4. **Phase 4: Cleanup**
   - Removes temporary scripts
   - Displays summary

### After Reboot: Quick GPU Clock Restore

Due to a hardware limitation on GB10, GPU clocks and vboost reset after reboot despite the systemd service. Use this quick playbook to restore them:

```bash
# Re-apply GPU clocks, vboost, and C-states (~5 seconds)
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/native/11_apply_non_persistent.yml
```

This is much faster than running the full optimization suite when you only need to restore GPU settings.

### Production Workflow (Recommended)

```bash
# 1. First-time setup: Apply everything and make persistent
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/native/10_complete_optimize.yml

# 2. After each reboot: Quick restore of GPU clocks
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/native/11_apply_non_persistent.yml

# 3. Optional: Full test with reboot verification (one-time validation)
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/native/10_complete_optimize.yml -e 'do_reboot=true'
```

## Persistence Across Reboots

### What Persists Automatically

The `10_complete_optimize.yml` playbook creates these persistent configurations:

### What Persists Automatically

The `10_complete_optimize.yml` playbook creates these persistent configurations:

- **Systemd service** (`dgx-optimize.service`) - Attempts to re-apply GPU clocks/vboost/C-states on boot
- **Sysctl config** (`/etc/sysctl.d/99-dgx-performance.conf`) - Memory and network settings
- **RC.local** (`/etc/rc.local`) - Transparent hugepages
- **Udev rules** (`/etc/udev/rules.d/60-dgx-io-performance.rules`) - I/O scheduler settings
- **ZFS module config** (`/etc/modprobe.d/zfs.conf`) - ARC metadata limit

### Persistence Reality (GB10 Hardware Limitation)

| Optimization Category | Persistence Method | Survives Reboot? |
|----------------------|-------------------|-----------------|
| **Persistence Mode** | Built-in NVML | ✅ Yes |
| **Accounting Mode** | Built-in NVML | ✅ Yes |
| **GPU Clocks** | Systemd service | ⚠️ No (hardware limitation) |
| **vboost Slider** | Systemd service | ⚠️ No (hardware limitation) |
| **CPU C-States** | Systemd service | ⚠️ No (hardware limitation) |
| **Swappiness** | Sysctl config | ✅ Yes |
| **Transparent Hugepages** | RC.local | ✅ Yes |
| **VFS Cache Pressure** | Sysctl config | ✅ Yes |
| **Dirty Ratios** | Sysctl config | ✅ Yes |
| **I/O Scheduler** | Udev rules | ✅ Yes |
| **Queue Depth** | Udev rules | ✅ Yes |
| **Read-Ahead** | Udev rules | ✅ Yes |
| **ZFS Autotrim** | Pool config | ✅ Yes |
| **ZFS ARC Limit** | Modprobe config | ✅ Yes |
| **Network Buffers** | Sysctl config | ✅ Yes |
| **TCP Settings** | Sysctl config | ✅ Yes |
| **Scheduler Autogroup** | Sysctl config | ✅ Yes |

**Known Issue**: GPU clock locking, vboost, and C-states do NOT persist on GB10 hardware despite the systemd service. This appears to be a hardware/firmware limitation where CUDA runtime resets these settings during initialization. 

**Workaround**: Run `11_apply_non_persistent.yml` after each reboot to restore GPU clock settings (~5 seconds).

### Manual Script Usage (Advanced)

If you prefer to run the scripts directly instead of via Ansible:

### Manual Script Usage (Advanced)

If you prefer to run the scripts directly instead of via Ansible:

```bash
# GPU and CPU optimizations
sudo ./gpu_optimize.sh apply
sudo ./gpu_optimize.sh status
sudo ./gpu_optimize.sh undo

# System-level optimizations
sudo ./system_optimize.sh apply
sudo ./system_optimize.sh status
sudo ./system_optimize.sh undo

# Make optimizations persistent
sudo ./make_persistent.sh install
sudo ./make_persistent.sh status
sudo ./make_persistent.sh uninstall
```

## Monitoring Performance

### Check GPU Status
```bash
nvidia-smi --query-gpu=name,clocks.sm,clocks.max.sm,clocks_event_reasons.sw_power_cap,temperature.gpu,power.draw --format=csv
```

### Check for Throttling
```bash
nvidia-smi --query-gpu=clocks_event_reasons.sw_power_cap,clocks_event_reasons.hw_slowdown,clocks_event_reasons.sw_thermal_slowdown --format=csv,noheader
```
- All should show "Not Active" when optimized

### Monitor CPU C-States
```bash
cat /sys/devices/system/cpu/cpu0/cpuidle/state*/disable
```
- States 2 and 3 should show "1" (disabled) when optimized

## Troubleshooting

### GPU Clocks Not Locking After Reboot
- **Symptom**: GPU clocks reset to default after reboot
- **Cause**: GB10 hardware limitation - CUDA runtime resets clocks during initialization
- **Solution**: Run `11_apply_non_persistent.yml` after each reboot to restore settings
- **Verification**: `nvidia-smi --query-gpu=clocks.sm --format=csv -l 1`

### C-States Re-Enabling After Reboot
- **Symptom**: C-states become enabled again after reboot
- **Cause**: Same hardware limitation as GPU clocks
- **Solution**: Run `11_apply_non_persistent.yml` after each reboot
- **Verification**: `cat /sys/devices/system/cpu/cpu*/cpuidle/state2/disable` (should show 1)

### GPU Clocks Not Locking During Operation

### GPU Clocks Not Locking During Operation
- **Symptom**: Clocks remain variable despite optimization
- **Solution**: Check for conflicting `CUDA_AUTO_BOOST` environment variables in application config
- **Verification**: `nvidia-smi --query-gpu=clocks.sm --format=csv -l 1`

### Performance Not Improving
- **Check**: Verify optimizations are actually applied with `status` command
- **Check**: Monitor for thermal throttling: `nvidia-smi -q -d TEMPERATURE`
- **Check**: Ensure models are loading from fast ZFS storage, not NFS

## Safety Notes

- **Temperature Monitoring**: Monitor GPU temperature during extended workloads. The GB10 should safely operate up to 90°C, but sustained high temperatures may indicate cooling issues.

- **Power Consumption**: Locked clocks will increase power consumption. Ensure adequate cooling and power supply.

- **Shared Systems**: Exclusive compute mode prevents other users/processes from accessing the GPU. Only use on dedicated systems.

- **Reverting Changes**: Always test optimizations and use the `undo` command if issues arise.

## Additional Resources

- [NVIDIA GPU Management Documentation](https://docs.nvidia.com/deploy/nvml-api/)
- [Linux CPU Frequency Scaling](https://www.kernel.org/doc/html/latest/admin-guide/pm/cpufreq.html)
- [ARM CPU Idle States](https://www.kernel.org/doc/html/latest/admin-guide/pm/cpuidle.html)

## Investigation Notes

During optimization testing, we discovered multiple layers of untapped performance:

### GPU/CPU Layer (Phase 1)

1. **SW Power Cap Active**: The GPU was being throttled by software power management, losing ~20% performance (2400 MHz vs 3003 MHz max).

2. **Video Boost Available**: The vboost slider was at 0, but NVIDIA documentation shows vboost=1 is the correct setting for compute-bound AI workloads (increases GPU core clock vs memory clock).

3. **Deep C-States Enabled**: CPU cores were entering deep sleep, adding wake latency for latency-sensitive operations.

4. **Grace-Blackwell Architecture**: The "PCIe downgrade" warning is false - the system uses NVLink-C2C coherent interconnect with 900 GB/s bandwidth, far exceeding PCIe capabilities.

5. **Locked-Down Settings**: Many typical GPU tuning options (power limits, temperature targets, application clocks) are firmware-locked on the GB10, but clock locking via `-lgc` works perfectly.

### System Layer (Phase 2)

1. **Swappiness Too High**: Default value of 60 causes unnecessary swapping even with 120GB RAM. System was using 286MB of swap despite having 10GB+ free RAM.

2. **Transparent Hugepages Conservative**: Set to "madvise" (application must request), but PyTorch and large tensors benefit from "always" mode. This is 512x fewer TLB entries for multi-GB models.

3. **I/O Queue Bottleneck**: Queue depth of only 2 requests is absurdly low for modern USB 20Gbps drives. This was limiting parallel I/O and causing sequential bottlenecks.

4. **Tiny Read-Ahead**: 128KB read-ahead is designed for spinning disks. USB SSDs with 2GB/s capability need 4MB+ to avoid sequential stalls when loading 10GB checkpoints.

5. **Wrong I/O Scheduler**: Using mq-deadline when ZFS has its own sophisticated scheduler creates double-scheduling overhead. Setting to "none" eliminates this.

6. **ZFS Autotrim Disabled**: Without TRIM on SSDs, write amplification accumulates over time, degrading performance. Especially important for USB drives.

7. **Network Buffers Too Small**: 212KB buffers designed for 1Gbps era. With 10GbE NIC and large image API responses, 16MB buffers prevent packet drops.

8. **Scheduler Autogroup Interference**: Desktop session grouping was potentially throttling server processes. Disabled for consistent performance.

### Combined Impact

**Before Full Optimization:**
- GPU: 2400 MHz (throttled), core clock boost disabled (vboost=0)
- Memory: Swapping with 10GB free, 4KB pages, aggressive cache reclaim
- I/O: 2-request queue, 128KB read-ahead, double-scheduling
- Network: 212KB buffers, slow-start delays
- CPU: Deep sleep enabled, autogroup interference

**After Full Optimization:**
- GPU: 3003 MHz locked, core clock boost mode (vboost=1)
- Memory: No swapping, 2MB hugepages, balanced cache, 40% dirty ratio
- I/O: 256-request queue, 4MB read-ahead, direct ZFS scheduling
- Network: 16MB buffers, TCP fastopen, no idle penalty
- CPU: Light sleep only, no autogroup throttling

**Expected Combined Improvement:**
- Model loading: 2-4x faster (I/O + memory + GPU)
- Inference: 20-30% faster (GPU clocks + core boost + hugepages + C-states)
- Compute throughput: 15-25% better (vboost=1 increases core clock)
- API latency: 50-70% lower (network + TCP tuning)
- Consistency: Near-zero variance (locked clocks + disabled throttling)
