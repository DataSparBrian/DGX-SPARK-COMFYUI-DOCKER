# ComfyUI Deployment for NVIDIA DGX Spark

Production-grade Ansible automation for deploying ComfyUI on NVIDIA DGX Spark systems with Blackwell GB10 GPU architecture.

## Overview

This repository provides infrastructure-as-code for automated ComfyUI deployment targeting NVIDIA DGX Spark platforms with Blackwell GB10 GPUs (compute capability 12.1). The deployment architecture leverages native installation patterns with systemd service management, delivering optimized performance through PyTorch 2.9.1+cu130, custom-compiled sageattention with sm_121a kernel support, and production-hardened configuration management.

## Deployment Options

### Native Installation (Production Ready)

The native deployment path provides complete lifecycle management for ComfyUI on bare-metal DGX Spark systems. This is the recommended approach for production workloads requiring maximum performance and stability.

**Status:** Production ready and validated

**Documentation:** [Native Deployment Guide](ansible/playbooks/native/README.md)

**Features:**
- Systemd service management with automatic restart policies
- Multi-user access control via group-based permissions
- NFS integration for shared model repositories
- Parallel asynchronous custom node installation
- Custom-built sageattention with Blackwell sm_121a support
- Custom-built Triton with sm_121a PTX compiler support
- Comprehensive CUDA optimization settings
- Idempotent playbooks enabling safe re-execution

### Docker Deployment (Development)

Containerized deployment using NVIDIA NGC PyTorch base images.

**Status:** Development in progress, not production ready

**Location:** `docker/` directory

**Note:** The Docker deployment path is currently incomplete and should not be used for production workloads. Native deployment is the supported production path

## Quick Start

For complete installation instructions, configuration reference, and troubleshooting guidance, refer to the [Native Deployment Guide](ansible/playbooks/native/README.md).

### Prerequisites

- NVIDIA DGX Spark with Blackwell GB10 GPU (compute capability 12.1)
- Ubuntu 24.04 LTS with CUDA 13.0 drivers and toolkit
- Ansible 2.9 or later on control machine
- SSH access with sudo privileges to target system

### Basic Deployment Sequence

```bash
cd ansible/playbooks/native

# Step 1: Install ComfyUI with PyTorch cu130, sageattention, and Triton
ansible-playbook -i ../../inventory/hosts.ini 01_install_update_comfyui.yml

# Step 2: Configure NFS symlinks (optional, skip if using local storage)
ansible-playbook -i ../../inventory/hosts.ini 02_symlink_models_input_output.yml

# Step 3: Install custom node extensions
ansible-playbook -i ../../inventory/hosts.ini 03_install_recommended_plugins.yml

# Step 4: Deploy as systemd service
ansible-playbook -i ../../inventory/hosts.ini 04_run_as_service.yml

# Step 5: Install sageattention with Blackwell support
ansible-playbook -i ../../inventory/hosts.ini 09_install_sageattention_blackwell.yml
```

**Access ComfyUI:** `http://<dgx_spark_ip>:8188`

## Documentation

- **[Native Deployment Guide](ansible/playbooks/native/README.md)** - Complete installation procedures, configuration reference, playbook details, and troubleshooting
- **[SageAttention Blackwell Installation](ansible/playbooks/native/09_install_sageattention_blackwell.md)** - Custom Triton and sageattention build procedures for sm_121a architecture

## Repository Structure

```
ansible/
├── inventory/
│   ├── hosts.ini                               # Target host definitions
│   └── group_vars/
│       └── all.yml                             # Centralized configuration variables
└── playbooks/
    └── native/
        ├── 01_install_update_comfyui.yml       # Core installation (idempotent)
        ├── 02_symlink_models_input_output.yml  # NFS storage integration
        ├── 03_install_recommended_plugins.yml  # Custom node deployment
        ├── 04_run_as_service.yml               # Systemd service creation
        ├── 05_restart_service.yml              # Service restart utility
        ├── 06_pause_service.yml                # Service pause utility
        ├── 07_start_service.yml                # Service start utility
        ├── 08_stop_remove_service.yml          # Service removal
        ├── 09_install_sageattention_blackwell.yml  # Blackwell-specific optimization
        ├── 99_nuke_comfy.yml                   # Clean removal for testing
        └── README.md                           # Comprehensive documentation

docker/
├── Dockerfile.comfyui-dgx                      # Base Dockerfile (incomplete)
└── entrypoint.sh                               # Container entrypoint (incomplete)
```

## Configuration Management

Primary configuration is managed through `ansible/inventory/group_vars/all.yml`. This file controls:

- Installation paths and Python environment settings
- Multi-user access control parameters
- CUDA architecture and PyTorch version specifications
- ComfyUI service configuration (flags, environment variables)
- NFS mount point definitions
- Custom node repository list

Refer to the [Native Deployment Guide](ansible/playbooks/native/README.md) for detailed configuration parameters.

## Technical Highlights

### Blackwell GB10 Optimization

The deployment architecture includes specialized support for NVIDIA Blackwell GB10 architecture:

- **Custom SageAttention Build:** Compiled from PR 297 with native sm_121a CUDA kernel support
- **Custom Triton Build:** Built from main branch with sm_121a PTX compiler support (addresses official Triton 3.5.1 limitations)
- **CUDA Cache Optimization:** Enabled 4GB kernel cache for improved repeated execution performance
- **Managed Memory Allocation:** Configured for optimal Blackwell memory management patterns
- **BF16 Precision:** Native bfloat16 support leveraging Blackwell tensor core capabilities

### Performance Characteristics

Validated for production workloads with the following performance profile:

- Continuous operation exceeding 10 hours without service interruption
- High-resolution image generation without out-of-memory conditions
- Complex workflow execution including face swap processing (ReActor nodes)
- 2-3x throughput improvement compared to containerized deployment alternatives
- Parallel custom node installation reducing setup time from 30+ minutes to approximately 5 minutes

### Environment Configuration

The deployment configures 20 CUDA and PyTorch environment variables optimized for Blackwell architecture, including:

- CUDA cache management and allocation strategies
- Device visibility and connection limits
- Module loading and launch blocking behavior
- Workspace configuration for deterministic operations
- Telemetry and diagnostic settings

Complete environment variable documentation is available in the [Native Deployment Guide](ansible/playbooks/native/README.md).

## License

See [LICENSE](LICENSE) for details.

