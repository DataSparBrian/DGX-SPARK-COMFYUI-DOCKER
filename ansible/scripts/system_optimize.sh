#!/bin/bash
# System Performance Optimization Script for DGX Spark
# Covers memory, I/O, network, and ZFS tuning beyond GPU/CPU

set -e

ACTION="${1:-apply}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

apply_optimizations() {
    log_info "Applying system performance optimizations..."
    
    # ========================================
    # Memory Optimizations
    # ========================================
    
    log_info "Setting swappiness to 10 (reduce swap usage)..."
    # With 120GB RAM, we want to avoid swap except extreme cases
    sysctl -w vm.swappiness=10
    
    log_info "Enabling transparent hugepages (always)..."
    # Large contiguous memory allocations benefit massively from hugepages
    echo always > /sys/kernel/mm/transparent_hugepage/enabled
    echo always > /sys/kernel/mm/transparent_hugepage/defrag
    
    log_info "Tuning memory cache pressure..."
    # Lower value = keep more file cache (good for model loading)
    sysctl -w vm.vfs_cache_pressure=50
    
    log_info "Setting dirty ratio for better write performance..."
    # Higher dirty ratio = more buffered writes before flush
    sysctl -w vm.dirty_ratio=40
    sysctl -w vm.dirty_background_ratio=10
    
    # ========================================
    # I/O Scheduler Optimizations
    # ========================================
    
    log_info "Optimizing I/O queue depths for USB 20Gbps drives..."
    # Find ZFS pool devices (sda, sdb based on discovery)
    for dev in sda sdb; do
        if [ -d "/sys/block/$dev/queue" ]; then
            log_info "  Tuning /dev/$dev..."
            
            # Increase queue depth for better throughput
            echo 256 > /sys/block/$dev/queue/nr_requests 2>/dev/null || true
            
            # Increase read-ahead for sequential model loading
            echo 4096 > /sys/block/$dev/queue/read_ahead_kb 2>/dev/null || true
            
            # Set scheduler to none for ZFS (ZFS does its own scheduling)
            echo none > /sys/block/$dev/queue/scheduler 2>/dev/null || log_warn "Could not set scheduler for $dev"
        fi
    done
    
    # ========================================
    # ZFS Optimizations
    # ========================================
    
    log_info "Enabling ZFS autotrim (SSD health)..."
    zpool set autotrim=on data_pool_a 2>/dev/null || log_warn "Could not enable autotrim"
    
    log_info "Optimizing ZFS ARC for AI workloads..."
    # Increase ARC metadata for better directory/file lookup performance
    echo 8589934592 > /sys/module/zfs/parameters/zfs_arc_meta_limit 2>/dev/null || true  # 8GB
    
    log_info "Tuning ZFS prefetch for sequential reads..."
    # Enable aggressive prefetching for model loading
    echo 1 > /sys/module/zfs/parameters/zfs_prefetch_disable && \
    echo 0 > /sys/module/zfs/parameters/zfs_prefetch_disable 2>/dev/null || true
    
    # ========================================
    # Network Optimizations
    # ========================================
    
    log_info "Increasing network buffer sizes (API performance)..."
    # Bigger buffers = better throughput for API requests
    sysctl -w net.core.rmem_max=16777216      # 16MB receive
    sysctl -w net.core.wmem_max=16777216      # 16MB send
    sysctl -w net.core.rmem_default=1048576   # 1MB default receive
    sysctl -w net.core.wmem_default=1048576   # 1MB default send
    sysctl -w net.core.netdev_max_backlog=5000
    
    log_info "Tuning TCP for low latency..."
    sysctl -w net.ipv4.tcp_fastopen=3
    sysctl -w net.ipv4.tcp_slow_start_after_idle=0
    
    # ========================================
    # Process Scheduler Optimizations
    # ========================================
    
    log_info "Disabling scheduler autogroup (consistent performance)..."
    # Prevents desktop session grouping from affecting server processes
    sysctl -w kernel.sched_autogroup_enabled=0
    
    # ========================================
    # Verification
    # ========================================
    
    echo ""
    log_info "Current System Settings:"
    echo ""
    echo "=== Memory ==="
    echo "Swappiness: $(cat /proc/sys/vm/swappiness)"
    echo "Transparent Hugepages: $(cat /sys/kernel/mm/transparent_hugepage/enabled)"
    echo "VFS Cache Pressure: $(cat /proc/sys/vm/vfs_cache_pressure)"
    echo "Dirty Ratio: $(cat /proc/sys/vm/dirty_ratio)"
    echo ""
    
    echo "=== I/O (sda) ==="
    if [ -d "/sys/block/sda/queue" ]; then
        echo "Scheduler: $(cat /sys/block/sda/queue/scheduler)"
        echo "Queue Depth: $(cat /sys/block/sda/queue/nr_requests)"
        echo "Read-ahead: $(cat /sys/block/sda/queue/read_ahead_kb) KB"
    fi
    echo ""
    
    echo "=== ZFS ==="
    zpool get autotrim data_pool_a 2>/dev/null | grep autotrim || true
    echo "ARC Meta Limit: $(cat /sys/module/zfs/parameters/zfs_arc_meta_limit) bytes"
    echo "Prefetch: $(cat /sys/module/zfs/parameters/zfs_prefetch_disable) (0=enabled)"
    echo ""
    
    echo "=== Network ==="
    echo "Max RX Buffer: $(cat /proc/sys/net/core/rmem_max)"
    echo "Max TX Buffer: $(cat /proc/sys/net/core/wmem_max)"
    echo "Netdev Backlog: $(cat /proc/sys/net/core/netdev_max_backlog)"
    echo ""
    
    echo "=== Scheduler ==="
    echo "Autogroup: $(cat /proc/sys/kernel/sched_autogroup_enabled) (0=disabled)"
    
    echo ""
    log_info "✓ All system optimizations applied!"
}

undo_optimizations() {
    log_info "Reverting system to default settings..."
    
    # Memory defaults
    log_info "Resetting memory settings to defaults..."
    sysctl -w vm.swappiness=60
    echo madvise > /sys/kernel/mm/transparent_hugepage/enabled
    echo madvise > /sys/kernel/mm/transparent_hugepage/defrag
    sysctl -w vm.vfs_cache_pressure=100
    sysctl -w vm.dirty_ratio=20
    sysctl -w vm.dirty_background_ratio=10
    
    # I/O scheduler defaults
    log_info "Resetting I/O scheduler settings..."
    for dev in sda sdb; do
        if [ -d "/sys/block/$dev/queue" ]; then
            echo 128 > /sys/block/$dev/queue/nr_requests 2>/dev/null || true
            echo 128 > /sys/block/$dev/queue/read_ahead_kb 2>/dev/null || true
            echo mq-deadline > /sys/block/$dev/queue/scheduler 2>/dev/null || true
        fi
    done
    
    # ZFS defaults
    log_info "Resetting ZFS settings..."
    zpool set autotrim=off data_pool_a 2>/dev/null || true
    
    # Network defaults
    log_info "Resetting network settings..."
    sysctl -w net.core.rmem_max=212992
    sysctl -w net.core.wmem_max=212992
    sysctl -w net.core.rmem_default=212992
    sysctl -w net.core.wmem_default=212992
    sysctl -w net.core.netdev_max_backlog=1000
    sysctl -w net.ipv4.tcp_fastopen=1
    sysctl -w net.ipv4.tcp_slow_start_after_idle=1
    
    # Scheduler defaults
    log_info "Resetting scheduler settings..."
    sysctl -w kernel.sched_autogroup_enabled=1
    
    echo ""
    log_info "✓ All settings reverted to defaults!"
}

show_status() {
    log_info "Current System Performance Settings:"
    
    echo ""
    echo "=== Memory Configuration ==="
    echo "Swappiness: $(cat /proc/sys/vm/swappiness) (default: 60, optimized: 10)"
    echo "Transparent Hugepages: $(cat /sys/kernel/mm/transparent_hugepage/enabled)"
    echo "VFS Cache Pressure: $(cat /proc/sys/vm/vfs_cache_pressure) (default: 100, optimized: 50)"
    echo "Dirty Ratio: $(cat /proc/sys/vm/dirty_ratio)% (default: 20, optimized: 40)"
    echo ""
    
    echo "=== Memory Usage ==="
    free -h
    echo ""
    
    echo "=== I/O Configuration (sda) ==="
    if [ -d "/sys/block/sda/queue" ]; then
        echo "Scheduler: $(cat /sys/block/sda/queue/scheduler)"
        echo "Queue Depth: $(cat /sys/block/sda/queue/nr_requests) (default: 128, optimized: 256)"
        echo "Read-ahead: $(cat /sys/block/sda/queue/read_ahead_kb) KB (default: 128, optimized: 4096)"
    fi
    echo ""
    
    echo "=== ZFS Configuration ==="
    zpool get autotrim data_pool_a 2>/dev/null | tail -n1 || true
    echo "ARC Meta Limit: $(cat /sys/module/zfs/parameters/zfs_arc_meta_limit) bytes"
    echo "Prefetch Disabled: $(cat /sys/module/zfs/parameters/zfs_prefetch_disable) (0=enabled, 1=disabled)"
    echo ""
    
    echo "=== Network Buffers ==="
    echo "Max RX: $(cat /proc/sys/net/core/rmem_max) bytes (default: 212992, optimized: 16777216)"
    echo "Max TX: $(cat /proc/sys/net/core/wmem_max) bytes (default: 212992, optimized: 16777216)"
    echo "Backlog: $(cat /proc/sys/net/core/netdev_max_backlog) (default: 1000, optimized: 5000)"
    echo ""
    
    echo "=== Scheduler ==="
    echo "Autogroup: $(cat /proc/sys/kernel/sched_autogroup_enabled) (1=enabled, 0=disabled for performance)"
}

show_usage() {
    cat << EOF
System Performance Optimization Script for DGX Spark

Usage: $0 [apply|undo|status]

Commands:
  apply   - Apply system-level performance optimizations (default)
  undo    - Revert to default system settings
  status  - Show current system configuration

Optimizations Applied:
  Memory:
    - Swappiness reduced to 10 (avoid swap with 120GB RAM)
    - Transparent hugepages always enabled (large allocations)
    - VFS cache pressure lowered to 50 (better file caching)
    - Dirty ratios increased (better write buffering)
  
  I/O:
    - Queue depth increased to 256 (better throughput)
    - Read-ahead increased to 4MB (sequential model loading)
    - Scheduler set to 'none' (ZFS does its own I/O scheduling)
  
  ZFS:
    - Autotrim enabled (SSD health on USB drives)
    - ARC metadata limit increased (faster directory ops)
    - Prefetch optimized (sequential read performance)
  
  Network:
    - Buffer sizes increased to 16MB (API throughput)
    - TCP fastopen enabled (lower latency)
    - No slow-start after idle (consistent performance)
  
  Scheduler:
    - Autogroup disabled (no desktop session interference)

Note: 
  - Must be run as root/sudo
  - These settings do NOT persist across reboots
  - Run on boot or create systemd service for persistence
  - Complement with gpu_optimize.sh for full system tuning

EOF
}

# Main execution
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root"
    exit 1
fi

case "$ACTION" in
    apply)
        apply_optimizations
        ;;
    undo)
        undo_optimizations
        ;;
    status)
        show_status
        ;;
    help|--help|-h)
        show_usage
        ;;
    *)
        log_error "Unknown action: $ACTION"
        show_usage
        exit 1
        ;;
esac

exit 0
