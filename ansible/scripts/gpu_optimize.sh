#!/bin/bash
# GPU Performance Optimization Script for DGX Spark (Grace-Blackwell)
# This script applies maximum performance settings for NVIDIA GB10 GPU and ARM CPU

set -e

ACTION="${1:-apply}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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
    log_info "Applying GPU and CPU performance optimizations..."
    
    # ========================================
    # NVIDIA GPU Optimizations
    # ========================================
    
    log_info "Setting GPU persistence mode (reduces driver load latency)..."
    nvidia-smi -pm 1 || log_warn "Failed to set persistence mode"
    
    # DISABLED: Exclusive compute mode conflicts with desktop/Xorg using the GPU
    # log_info "Setting exclusive compute mode (dedicated GPU access)..."
    # nvidia-smi -c 3 || log_warn "Failed to set exclusive compute mode"
    
    log_info "Locking GPU clocks to maximum (3003 MHz)..."
    nvidia-smi -lgc 3003,3003 || log_warn "Failed to lock GPU clocks"
    
    log_info "Setting GPU core clock boost mode (increases GPU core vs memory clock)..."
    nvidia-smi boost-slider --vboost 1 || log_warn "Failed to set core clock boost"
    
    log_info "Enabling accounting mode (process tracking)..."
    nvidia-smi -am 1 || log_warn "Failed to enable accounting mode"
    
    # ========================================
    # ARM CPU Optimizations
    # ========================================
    
    log_info "Disabling deep C-states (reduces CPU wake latency)..."
    for i in $(seq 0 19); do
        # Disable C-state 2 (deeper sleep)
        if [ -f "/sys/devices/system/cpu/cpu${i}/cpuidle/state2/disable" ]; then
            echo 1 > /sys/devices/system/cpu/cpu${i}/cpuidle/state2/disable 2>/dev/null || true
        fi
        # Disable C-state 3 (deepest sleep)
        if [ -f "/sys/devices/system/cpu/cpu${i}/cpuidle/state3/disable" ]; then
            echo 1 > /sys/devices/system/cpu/cpu${i}/cpuidle/state3/disable 2>/dev/null || true
        fi
    done
    log_info "Deep C-states disabled on all 20 CPU cores"
    
    # ========================================
    # Verification
    # ========================================
    
    echo ""
    log_info "Current GPU Status:"
    nvidia-smi --query-gpu=name,persistence_mode,compute_mode,clocks.sm,clocks.max.sm,temperature.gpu,power.draw --format=csv
    
    echo ""
    log_info "Video Boost Status:"
    nvidia-smi boost-slider -l
    
    echo ""
    log_info "CPU Governor Status:"
    cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor | sort -u
    
    echo ""
    log_info "CPU C-States (first core sample):"
    echo "State 0 (active): $(cat /sys/devices/system/cpu/cpu0/cpuidle/state0/disable)"
    echo "State 1 (light sleep): $(cat /sys/devices/system/cpu/cpu0/cpuidle/state1/disable)"
    echo "State 2 (deep sleep): $(cat /sys/devices/system/cpu/cpu0/cpuidle/state2/disable)"
    echo "State 3 (deepest sleep): $(cat /sys/devices/system/cpu/cpu0/cpuidle/state3/disable)"
    echo "(0=enabled, 1=disabled)"
    
    echo ""
    log_info "✓ All optimizations applied successfully!"
}

undo_optimizations() {
    log_info "Reverting GPU and CPU to default settings..."
    
    # ========================================
    # NVIDIA GPU Defaults
    # ========================================
    
    log_info "Resetting GPU clocks to default (auto-boost)..."
    nvidia-smi -rgc || log_warn "Failed to reset GPU clocks"
    
    log_info "Setting compute mode to default (shared)..."
    nvidia-smi -c 0 || log_warn "Failed to reset compute mode"
    
    log_info "Disabling persistence mode..."
    nvidia-smi -pm 0 || log_warn "Failed to disable persistence mode"
    
    log_info "Resetting core clock boost to default (0)..."
    nvidia-smi boost-slider --vboost 0 || log_warn "Failed to reset core clock boost"
    
    log_info "Disabling accounting mode..."
    nvidia-smi -am 0 || log_warn "Failed to disable accounting mode"
    
    # ========================================
    # ARM CPU Defaults
    # ========================================
    
    log_info "Re-enabling all C-states (power saving)..."
    for i in $(seq 0 19); do
        # Re-enable C-state 2
        if [ -f "/sys/devices/system/cpu/cpu${i}/cpuidle/state2/disable" ]; then
            echo 0 > /sys/devices/system/cpu/cpu${i}/cpuidle/state2/disable 2>/dev/null || true
        fi
        # Re-enable C-state 3
        if [ -f "/sys/devices/system/cpu/cpu${i}/cpuidle/state3/disable" ]; then
            echo 0 > /sys/devices/system/cpu/cpu${i}/cpuidle/state3/disable 2>/dev/null || true
        fi
    done
    log_info "All C-states re-enabled on all CPU cores"
    
    # ========================================
    # Verification
    # ========================================
    
    echo ""
    log_info "Current GPU Status:"
    nvidia-smi --query-gpu=name,persistence_mode,compute_mode,clocks.sm,clocks.max.sm,temperature.gpu,power.draw --format=csv
    
    echo ""
    log_info "Video Boost Status:"
    nvidia-smi boost-slider -l
    
    echo ""
    log_info "✓ All optimizations reverted to defaults!"
}

show_status() {
    log_info "Current Performance Settings:"
    
    echo ""
    echo "=== GPU Status ==="
    nvidia-smi --query-gpu=name,persistence_mode,compute_mode,clocks.sm,clocks.max.sm,clocks_event_reasons.sw_power_cap,temperature.gpu,power.draw --format=csv
    
    echo ""
    echo "=== Video Boost ==="
    nvidia-smi boost-slider -l
    
    echo ""
    echo "=== CPU Governor ==="
    cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor | sort -u
    
    echo ""
    echo "=== CPU C-States (CPU0 sample) ==="
    echo "State 0: $(cat /sys/devices/system/cpu/cpu0/cpuidle/state0/disable) (0=enabled)"
    echo "State 1: $(cat /sys/devices/system/cpu/cpu0/cpuidle/state1/disable) (0=enabled)"
    echo "State 2: $(cat /sys/devices/system/cpu/cpu0/cpuidle/state2/disable) (1=disabled for performance)"
    echo "State 3: $(cat /sys/devices/system/cpu/cpu0/cpuidle/state3/disable) (1=disabled for performance)"
}

show_usage() {
    cat << EOF
GPU Performance Optimization Script for DGX Spark

Usage: $0 [apply|undo|status]

Commands:
  apply   - Apply maximum performance optimizations (default)
  undo    - Revert to default balanced settings
  status  - Show current optimization status

Optimizations Applied:
  GPU:
    - Persistence mode (reduces driver load latency)
    - Exclusive compute mode (dedicated GPU access)
    - Locked clocks at 3003 MHz (removes throttling)
    - Core clock boost mode (GPU core > memory clock for compute)
    - Accounting mode enabled (process monitoring)
  
  CPU:
    - Deep C-states disabled (lower wake latency)
    - Governor already on 'performance' mode

Note: Must be run as root/sudo
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
