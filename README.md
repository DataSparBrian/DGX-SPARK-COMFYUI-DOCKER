# ComfyUI on NVIDIA DGX Spark

Production-grade Ansible automation for deploying ComfyUI on NVIDIA DGX Spark systems with Blackwell GB10 GPU architecture.

## What This Does

This repo automates the entire ComfyUI setup process on DGX Spark hardware. It handles everything from installing Python and CUDA dependencies to setting up a systemd service that runs on boot. The whole thing is built around Ansible playbooks so you can deploy consistently across multiple machines.

The native installation path is production-ready and has been running stable for 10+ hours straight with heavy workloads (face swaps, high-res generation, complex workflows). Docker deployment is still WIP and not ready yet.

## Why Native vs Docker?

Short answer: performance. The native install is 2-3x faster than containerized setups and doesn't have the memory overhead. For production workloads on expensive GPU hardware, that matters.

## What's Optimized Here

This setup is tuned specifically for the Blackwell GB10 architecture with unified memory fabric (compute capability 12.1):

**Precision & Attention:**
- **FP16 precision** - Force FP16 for unet/vae/text encoder (enables SageAttention, 2x smaller than FP32)
- **SageAttention enabled** - Fast attention for Blackwell tensor cores (requires FP16/BF16)
- **Flash Attention** - Included by default for standard workloads
- **No attention upcasting** - Keeps attention operations in FP16 for maximum speed

**Memory Management (Critical for Unified Memory):**
- **GPU-only mode** - Forces all models into GPU side of unified memory fabric
- **Zero caching** - `--cache-none` eliminates RAM spillover (30-40s load → seconds)
- **No memory mapping** - `--disable-mmap` forces direct GPU allocation
- **Disabled CUDA malloc** - Uses PyTorch's allocator optimized for unified memory
- **No pinned memory** - Reduces RAM overhead on unified fabric
- **Async offload** - Non-blocking model swapping for better pipeline

**CUDA Tuning:**
- **Single connection mode** - 1 CUDA connection, 1 copy connection (eliminates contention on unified fabric)
- **EAGER module loading** - Immediate kernel loading for predictable performance
- **Minimal CUBLAS workspace** - :0:0 config to reduce overhead
- **PyTorch 2.9.1 with CUDA 13.0** - Latest stable with Blackwell support

**System-level GPU optimizations** - Locked clocks, vboost, memory tuning, I/O optimizations (see `ansible/scripts/`)

**Performance Results:**
- Model loading: **30-40s → 2-3 seconds** (10-20x faster)
- Sampler speed: **20% faster** than default config
- Full GPU utilization (fans spinning at load)
- 105W power draw vs 650W for comparable discrete GPU (6x memory at 16% power)

## Quick Start

**What you need:**
- DGX Spark with Blackwell GB10 GPU
- Ubuntu 24.04 with CUDA 13.0 drivers installed
- Ansible on your local machine (WSL works fine)
- SSH access to the DGX with sudo

**Installation steps:**

```bash
cd ansible/playbooks/native

# 1. Install ComfyUI with PyTorch and flash-attention
ansible-playbook -i ../../inventory/hosts.ini 01_install_update_comfyui.yml

# 2. (Optional) Set up NFS storage for models - skip if using local storage
ansible-playbook -i ../../inventory/hosts.ini 02_symlink_models_input_output.yml

# 3. Install custom nodes (ComfyUI-Manager, Impact Pack, etc.)
ansible-playbook -i ../../inventory/hosts.ini 03_install_recommended_plugins.yml

# 4. Set up as a systemd service (auto-starts on boot)
ansible-playbook -i ../../inventory/hosts.ini 04_run_as_service.yml

# 5. (Optional) Install SageAttention - recommended for FLUX and large models
ansible-playbook -i ../../inventory/hosts.ini 09_install_sageattention_blackwell.yml

# 6. (Optional but recommended) Apply GPU optimizations for max performance
ansible-playbook -i ../../inventory/hosts.ini 10_complete_optimize.yml
```

Then open `http://<your-dgx-ip>:8188` and you're good to go.

**After reboots:** GPU clocks reset due to hardware limitations. Re-apply with:
```bash
ansible-playbook -i ../../inventory/hosts.ini 11_apply_non_persistent.yml
```

## Configuration

Everything is controlled through `ansible/inventory/group_vars/all.yml`:

**Core Settings:**
- Installation paths and Python/CUDA versions
- Service configuration (port, user, etc.)

**ComfyUI Flags (Optimized for Grace-Blackwell Unified Memory):**
```yaml
- "--gpu-only"              # Force GPU-side allocation on unified fabric
- "--cache-none"            # Zero caching = 10-20x faster model loads
- "--fp16-unet/vae/text-enc" # FP16 precision for SageAttention
- "--force-fp16"            # Enforce FP16 everywhere
- "--dont-upcast-attention" # Keep attention in FP16 for speed
- "--disable-mmap"          # Direct GPU memory allocation
- "--disable-cuda-malloc"   # Use PyTorch allocator
- "--async-offload"         # Non-blocking model swaps
- "--disable-pinned-memory" # Reduce RAM overhead
- "--use-sage-attention"    # Blackwell-optimized attention
- "--disable-xformers"      # Incompatible with sage attention
```

**CUDA Environment (Tuned for Unified Memory Fabric):**
```yaml
CUDA_MODULE_LOADING: "EAGER"              # Immediate kernel loading
CUDA_DEVICE_MAX_CONNECTIONS: "1"          # Single connection mode
CUDA_DEVICE_MAX_COPY_CONNECTIONS: "1"     # No connection contention
CUBLAS_WORKSPACE_CONFIG: ":0:0"           # Minimal workspace overhead
```

**Why These Settings Matter:**
Traditional discrete GPU optimizations (aggressive caching, pinned memory, high connection counts) actually **hurt** performance on Grace-Blackwell's unified memory architecture. This config forces everything GPU-side with zero caching overhead, resulting in 10-20x faster model loading and 20% faster inference.

Check the [Native Deployment Guide](ansible/playbooks/native/README.md) for all configuration options.

## What's Working

This has been tested and validated for:

## What's Working

This setup has been tested and works reliably with:

- **10+ hour continuous runs** without crashes or memory leaks
- **High-resolution image generation** (no OOM errors)
- **Complex workflows** with face swapping (ReActor nodes), upscaling, etc.
- **Parallel custom node installation** (5 minutes vs 30+ sequential)
- **System-level optimizations** for locked GPU clocks, memory tuning, I/O performance

## Where This Is At

**Current Status:** Native installation is solid and production-ready. This is as tuned as we're going to get for bare-metal deployment.

**Next Steps:** Docker packaging is next on the roadmap, but for now the native install works great and gives better performance anyway.

**GPU Optimization:** There's a full GPU optimization suite in `ansible/scripts/` with playbooks for locking clocks, tuning memory/I/O, and making it all persistent. Check the [GPU Optimization README](ansible/scripts/README.md) for details.

## File Structure

```
ansible/
├── inventory/
│   ├── hosts.ini                              # Your DGX Spark IPs
│   └── group_vars/all.yml                     # All the config knobs
├── playbooks/native/
│   ├── 01_install_update_comfyui.yml          # Main install
│   ├── 02_symlink_models_input_output.yml     # Storage setup
│   ├── 03_install_recommended_plugins.yml     # Custom nodes
│   ├── 04_run_as_service.yml                  # Systemd service
│   ├── 05-08_*.yml                            # Service management utils
│   ├── 09_install_sageattention_blackwell.yml # Optional FLUX optimization
│   ├── 10_complete_optimize.yml               # GPU/system tuning
│   ├── 11_apply_non_persistent.yml            # Post-reboot GPU restore
│   ├── 99_nuke_comfy.yml                      # Clean uninstall
│   └── README.md                              # Detailed docs
└── scripts/
    ├── gpu_optimize.sh                        # GPU clock locking, vboost
    ├── system_optimize.sh                     # Memory, I/O, network tuning
    ├── make_persistent.sh                     # Persistence configs
    └── README.md                              # Optimization guide

docker/                                         # WIP, not ready yet
```

## Docs

- **[Native Deployment Guide](ansible/playbooks/native/README.md)** - Full installation guide with all the details
- **[GPU Optimization README](ansible/scripts/README.md)** - Performance tuning for GB10
- **[SageAttention Installation](ansible/playbooks/native/09_install_sageattention_blackwell.md)** - Building sage attention for Blackwell

## Notes

**Unified Memory Architecture:** Grace-Blackwell's unified memory fabric is fundamentally different from discrete GPUs. Traditional optimizations like aggressive caching, reserve-vram, and high CUDA connection counts actually hurt performance. The config here is specifically tuned to force GPU-side allocation with zero caching overhead.

**SageAttention:** Requires FP16 or BF16 precision. FP32 will fall back to slow PyTorch attention. The `--force-fp16` config enables full SageAttention acceleration on Blackwell tensor cores.

**Model Loading Speed:** With `--cache-none` and direct GPU allocation, model loading went from 30-40 seconds to 2-3 seconds. This is the key optimization for Grace-Blackwell systems.

**GPU Clock Persistence:** Clock settings don't persist across reboots due to GB10 firmware behavior. Run playbook 11 after each boot (~5 seconds) to restore max clocks and vboost.

**Docker Status:** Docker deployment is in progress but not ready. Native install is production-ready and delivers better performance on unified memory architecture.

## License

See [LICENSE](LICENSE).

