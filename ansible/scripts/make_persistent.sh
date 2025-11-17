#!/bin/bash
# Persistence Configuration Script for DGX Spark Optimizations
# This script creates system configuration files to make optimizations permanent

set -e

ACTION="${1:-install}"

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

install_persistence() {
    log_info "Installing persistent optimization configurations..."
    
    # ========================================
    # Systemd Service for Boot-Time GPU/CPU Optimizations
    # ========================================
    
    log_info "Creating systemd service for GPU/CPU optimizations..."
    
    cat > /etc/systemd/system/dgx-optimize.service << 'EOF'
[Unit]
Description=DGX Spark Performance Optimizations
After=nvidia-persistenced.service multi-user.target network.target
Wants=nvidia-persistenced.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/bin/sh -c 'until nvidia-smi &>/dev/null; do sleep 1; done'
ExecStart=/opt/dgx-optimize/gpu_optimize.sh apply
ExecStop=/opt/dgx-optimize/gpu_optimize.sh undo
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    log_info "Creating optimization scripts directory..."
    mkdir -p /opt/dgx-optimize
    
    # Copy scripts to permanent location
    if [ -f "/tmp/gpu_optimize.sh" ]; then
        cp /tmp/gpu_optimize.sh /opt/dgx-optimize/
    elif [ -f "./gpu_optimize.sh" ]; then
        cp ./gpu_optimize.sh /opt/dgx-optimize/
    else
        log_warn "gpu_optimize.sh not found, service may not work"
    fi
    
    chmod +x /opt/dgx-optimize/gpu_optimize.sh 2>/dev/null || true
    
    # ========================================
    # Sysctl Configuration for Memory/Network
    # ========================================
    
    log_info "Creating sysctl configuration for memory and network..."
    
    cat > /etc/sysctl.d/99-dgx-performance.conf << 'EOF'
# DGX Spark Performance Optimizations
# Memory Management
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 40
vm.dirty_background_ratio = 10

# Network Performance
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.core.netdev_max_backlog = 5000

# TCP Optimization
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0

# Scheduler
kernel.sched_autogroup_enabled = 0
EOF
    
    # ========================================
    # Transparent Hugepages Configuration
    # ========================================
    
    log_info "Creating rc.local for transparent hugepages..."
    
    cat > /etc/rc.local << 'EOF'
#!/bin/bash
# DGX Spark boot-time optimizations

# Enable transparent hugepages (critical for AI workloads)
echo always > /sys/kernel/mm/transparent_hugepage/enabled
echo always > /sys/kernel/mm/transparent_hugepage/defrag

exit 0
EOF
    
    chmod +x /etc/rc.local
    
    # Create systemd service for rc.local if it doesn't exist
    if [ ! -f /etc/systemd/system/rc-local.service ]; then
        cat > /etc/systemd/system/rc-local.service << 'EOF'
[Unit]
Description=/etc/rc.local Compatibility
ConditionFileIsExecutable=/etc/rc.local
After=network.target

[Service]
Type=forking
ExecStart=/etc/rc.local start
TimeoutSec=0
RemainAfterExit=yes
GuessMainPID=no

[Install]
WantedBy=multi-user.target
EOF
    fi
    
    # ========================================
    # Udev Rules for I/O Optimization
    # ========================================
    
    log_info "Creating udev rules for I/O optimization..."
    
    cat > /etc/udev/rules.d/60-dgx-io-performance.rules << 'EOF'
# DGX Spark I/O Performance Rules
# Apply to all block devices used by ZFS (USB drives)

# Set scheduler to 'none' for ZFS drives (ZFS does its own I/O scheduling)
ACTION=="add|change", KERNEL=="sd[ab]", ATTR{queue/scheduler}="none"

# Increase queue depth for better throughput
ACTION=="add|change", KERNEL=="sd[ab]", ATTR{queue/nr_requests}="256"

# Increase read-ahead for sequential workloads (model loading)
ACTION=="add|change", KERNEL=="sd[ab]", ATTR{queue/read_ahead_kb}="4096"
EOF
    
    # ========================================
    # ZFS Module Parameters
    # ========================================
    
    log_info "Creating ZFS module configuration..."
    
    cat > /etc/modprobe.d/zfs.conf << 'EOF'
# DGX Spark ZFS Performance Tuning
# ARC metadata limit (8GB for large model directories)
options zfs zfs_arc_meta_limit=8589934592
EOF
    
    # ========================================
    # Enable Services
    # ========================================
    
    log_info "Enabling systemd services..."
    systemctl daemon-reload
    systemctl enable dgx-optimize.service 2>/dev/null || log_warn "Could not enable dgx-optimize service"
    systemctl enable rc-local.service 2>/dev/null || log_warn "Could not enable rc-local service"
    
    # Reload udev rules
    log_info "Reloading udev rules..."
    udevadm control --reload-rules 2>/dev/null || log_warn "Could not reload udev rules"
    udevadm trigger 2>/dev/null || log_warn "Could not trigger udev"
    
    # Apply sysctl settings now
    log_info "Applying sysctl settings..."
    sysctl -p /etc/sysctl.d/99-dgx-performance.conf 2>/dev/null || log_warn "Could not apply sysctl settings"
    
    # ========================================
    # Summary
    # ========================================
    
    echo ""
    log_info "Persistence Configuration Summary:"
    echo ""
    echo "✓ Systemd service: /etc/systemd/system/dgx-optimize.service"
    echo "  - Auto-applies GPU clocks, core boost, C-states on boot"
    echo "  - Status: $(systemctl is-enabled dgx-optimize.service 2>/dev/null || echo 'check manually')"
    echo ""
    echo "✓ Sysctl config: /etc/sysctl.d/99-dgx-performance.conf"
    echo "  - Memory: swappiness, cache pressure, dirty ratios"
    echo "  - Network: buffer sizes, TCP tuning"
    echo "  - Scheduler: autogroup disabled"
    echo ""
    echo "✓ RC.local: /etc/rc.local"
    echo "  - Transparent hugepages (always enabled)"
    echo ""
    echo "✓ Udev rules: /etc/udev/rules.d/60-dgx-io-performance.rules"
    echo "  - I/O scheduler, queue depth, read-ahead"
    echo ""
    echo "✓ ZFS module: /etc/modprobe.d/zfs.conf"
    echo "  - ARC metadata limit"
    echo ""
    log_info "✓ All persistence configurations installed!"
    log_info "Optimizations will now survive reboots"
}

uninstall_persistence() {
    log_info "Removing persistent optimization configurations..."
    
    # Stop and disable service
    systemctl stop dgx-optimize.service 2>/dev/null || true
    systemctl disable dgx-optimize.service 2>/dev/null || true
    
    # Remove files
    rm -f /etc/systemd/system/dgx-optimize.service
    rm -f /etc/sysctl.d/99-dgx-performance.conf
    rm -f /etc/rc.local
    rm -f /etc/systemd/system/rc-local.service
    rm -f /etc/udev/rules.d/60-dgx-io-performance.rules
    rm -f /etc/modprobe.d/zfs.conf
    rm -rf /opt/dgx-optimize
    
    systemctl daemon-reload
    udevadm control --reload-rules 2>/dev/null || true
    
    log_info "✓ All persistence configurations removed"
    log_warn "You may want to reboot to fully revert to defaults"
}

show_status() {
    log_info "Persistence Configuration Status:"
    echo ""
    
    echo "=== Systemd Service ==="
    if [ -f /etc/systemd/system/dgx-optimize.service ]; then
        echo "✓ Service file exists"
        echo "  Enabled: $(systemctl is-enabled dgx-optimize.service 2>/dev/null || echo 'no')"
        echo "  Active: $(systemctl is-active dgx-optimize.service 2>/dev/null || echo 'inactive')"
    else
        echo "✗ Service not installed"
    fi
    echo ""
    
    echo "=== Sysctl Configuration ==="
    if [ -f /etc/sysctl.d/99-dgx-performance.conf ]; then
        echo "✓ Sysctl config exists"
        echo "  Current swappiness: $(cat /proc/sys/vm/swappiness)"
        echo "  Current rmem_max: $(cat /proc/sys/net/core/rmem_max)"
    else
        echo "✗ Sysctl config not installed"
    fi
    echo ""
    
    echo "=== Transparent Hugepages ==="
    if [ -f /etc/rc.local ]; then
        echo "✓ RC.local exists"
        echo "  Current setting: $(cat /sys/kernel/mm/transparent_hugepage/enabled)"
    else
        echo "✗ RC.local not installed"
    fi
    echo ""
    
    echo "=== Udev Rules ==="
    if [ -f /etc/udev/rules.d/60-dgx-io-performance.rules ]; then
        echo "✓ Udev rules exist"
        if [ -d /sys/block/sda/queue ]; then
            echo "  sda scheduler: $(cat /sys/block/sda/queue/scheduler)"
            echo "  sda queue depth: $(cat /sys/block/sda/queue/nr_requests)"
            echo "  sda read-ahead: $(cat /sys/block/sda/queue/read_ahead_kb) KB"
        fi
    else
        echo "✗ Udev rules not installed"
    fi
    echo ""
    
    echo "=== ZFS Module Config ==="
    if [ -f /etc/modprobe.d/zfs.conf ]; then
        echo "✓ ZFS config exists"
        if [ -f /sys/module/zfs/parameters/zfs_arc_meta_limit ]; then
            echo "  ARC meta limit: $(cat /sys/module/zfs/parameters/zfs_arc_meta_limit) bytes"
        fi
    else
        echo "✗ ZFS config not installed"
    fi
}

show_usage() {
    cat << EOF
Persistence Configuration Script for DGX Spark

Usage: $0 [install|uninstall|status]

Commands:
  install   - Install persistent configuration files (default)
  uninstall - Remove all persistence configurations
  status    - Show current persistence status

What Gets Made Persistent:
  ✓ GPU clocks, core boost, C-states (via systemd service)
  ✓ Memory settings (via sysctl)
  ✓ Network buffers (via sysctl)
  ✓ Transparent hugepages (via rc.local)
  ✓ I/O scheduler settings (via udev rules)
  ✓ ZFS ARC limit (via modprobe config)

What's Already Persistent:
  ✓ GPU persistence mode
  ✓ GPU exclusive compute mode
  ✓ GPU accounting mode
  ✓ ZFS autotrim setting

Note: Must be run as root/sudo
EOF
}

# Main execution
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root"
    exit 1
fi

case "$ACTION" in
    install)
        install_persistence
        ;;
    uninstall)
        uninstall_persistence
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
