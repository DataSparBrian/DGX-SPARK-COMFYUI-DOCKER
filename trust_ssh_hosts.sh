#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./trust_ssh_hosts.sh hostsfile.ini [--key-path ~/.ssh/id_ed25519.pub]
#   ./trust_ssh_hosts.sh proxmox [--user root] [--key-path ~/.ssh/id_ed25519.pub] 10.0.10.8 10.0.10.1
#
# If first positional argument is an inventory file (INI), the script will parse it and extract
# hosts and their `ansible_user` if present. Example inventory files: `hosts-iris.ini`, `hosts_proxmox.ini`.
# If `--user` is provided it overrides per-host users. If the inventory contains multiple users,
# the script will prompt for a password per unique user; if a single user is used across hosts,
# it will prompt once.
# Prompts for password(s) and adds SSH keys to known_hosts; also pre-seeds SSH auth via sshpass.
#
# Supports: Ubuntu/Debian (apt), Arch Linux (pacman)
# WSL/Linux only.

# If first arg is a file, treat it as an inventory to parse; otherwise accept legacy mode/hosts args
ARG1=${1:-}
shift || true

# Optional flags: --user and --key-path
TARGET_USER=""
KEY_PATH=""
if [[ "${ARG1:-}" == "--user" ]]; then
  # legacy style: --user was passed as first argument
  TARGET_USER=${1:-}
  shift || true
  ARG1=${1:-}
  shift || true
fi

if [[ "${ARG1:-}" == "--key-path" ]]; then
  KEY_PATH=${1:-}
  shift || true
  ARG1=${1:-}
  shift || true
fi

# If ARG1 is a readable file, parse it as an inventory
INVENTORY_FILE=""
HOSTS=()
declare -A HOST_USER_MAP=()
if [[ -n "$ARG1" && -f "$ARG1" ]]; then
  INVENTORY_FILE="$ARG1"
  # Parse INI inventory: capture lines with host entries (skip [groups], :children lists and var lines)
  in_children_section=0
  while IFS= read -r raw; do
    line="$raw"
    # strip comments starting with ; or #
    line="${line%%;*}"
    line="${line%%#*}"
    # trim
    line="$(echo "$line" | sed -e 's/^\s*//' -e 's/\s*$//')"
    if [[ -z "$line" ]]; then
      continue
    fi
    # detect and skip a :children section (lines under [group:children] are group names, not hosts)
    if [[ "$line" =~ ^\[.*:children\]$ ]]; then
      in_children_section=1
      continue
    fi
    # any other header ends a children section and is not a host header
    if [[ "$line" =~ ^\[.*\]$ ]]; then
      in_children_section=0
      continue
    fi
    if [[ $in_children_section -eq 1 ]]; then
      # skip group names listed under a :children header
      continue
    fi
    # host lines start with host/ip (first token). If the first token contains '=' it's a var - skip.
    host_token="$(awk '{print $1}' <<< "$line")"
    if [[ "$host_token" == *=* ]]; then
      # first token is a key=value var, not a host
      continue
    fi
    # only accept simple IPv4 or hostname tokens
    if [[ ! ( "$host_token" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ || "$host_token" =~ ^[A-Za-z0-9._-]+$ ) ]]; then
      continue
    fi
    # ignore lines that are not an address/hostname
    if [[ -z "$host_token" ]]; then
      continue
    fi
    # extract ansible_user if present
    user_token=""
    if grep -q "ansible_user=" <<< "$line"; then
      user_token=$(grep -oP 'ansible_user=\K[^ ]+' <<< "$line" || true)
    fi
    HOSTS+=("$host_token")
    HOST_USER_MAP["$host_token"]="$user_token"
  done < "$INVENTORY_FILE"
else
  # legacy: ARG1 could be a mode (proxmox/nodes) or an IP/hostname; collect remaining args as hosts
  if [[ -n "$ARG1" ]]; then
    # if ARG1 looks like an IP or simple hostname, treat it as a host
    if [[ "$ARG1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ || "$ARG1" =~ ^[A-Za-z0-9._-]+$ ]]; then
      HOSTS+=("$ARG1")
    else
      MODE="$ARG1"
    fi
  fi
  # remaining args are host IPs or hostnames
  while [[ $# -gt 0 ]]; do
    HOSTS+=("$1")
    shift
  done
fi

if [[ ${#HOSTS[@]} -eq 0 ]]; then
  echo "Usage: $0 <hosts_inventory.ini> [--key-path <pubkey>] OR $0 <mode> [--user <user>] <host1> [host2 ...]"
  exit 1
fi

# ensure sshpass exists
if ! command -v sshpass >/dev/null 2>&1; then
  echo "Installing sshpass (requires sudo)..."
  # Detect distro and use appropriate package manager
  if command -v pacman >/dev/null 2>&1; then
    # Arch Linux
    sudo pacman -Sy --noconfirm sshpass
  elif command -v apt-get >/dev/null 2>&1; then
    # Ubuntu/Debian
    sudo apt-get update -y && sudo apt-get install -y sshpass
  else
    echo "ERROR: Unsupported distribution. Please install sshpass manually."
    exit 3
  fi
fi

# If we parsed an inventory, build unique user list
declare -A UNIQUE_USERS=()
declare -A USER_TO_PASSWORD=()
if [[ -n "$INVENTORY_FILE" ]]; then
  # If TARGET_USER override provided, apply to all hosts
  if [[ -n "$TARGET_USER" ]]; then
    for h in "${HOSTS[@]}"; do
      HOST_USER_MAP["$h"]="$TARGET_USER"
    done
  fi
  # Default empty users to root
  for h in "${HOSTS[@]}"; do
    if [[ -z "${HOST_USER_MAP[$h]}" ]]; then
      HOST_USER_MAP[$h]="root"
    fi
    u="${HOST_USER_MAP[$h]}"
    UNIQUE_USERS["$u"]=1
  done
  # Prompt for passwords per unique user
  for u in "${!UNIQUE_USERS[@]}"; do
    read -s -p "Enter SSH password for user ${u}: " pw
    echo
    USER_TO_PASSWORD["$u"]="$pw"
  done
else
  # legacy mode: use TARGET_USER or derive from MODE
  if [[ -z "$TARGET_USER" ]]; then
    if [[ "$MODE" == "proxmox" ]]; then
      TARGET_USER="root"
    else
      TARGET_USER="adm4n"
    fi
  fi
  read -s -p "Enter SSH password for ${MODE:-targets} (user ${TARGET_USER}): " SSH_PASS
  echo
fi

# Determine which public key to use (WSL/Linux only)
if [[ -z "$KEY_PATH" ]]; then
  # Ensure ~/.ssh exists
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  # Prefer an existing public key if present (do not overwrite)
  if [[ -f "$HOME/.ssh/id_ed25519.pub" ]]; then
    KEY_PATH="$HOME/.ssh/id_ed25519.pub"
  elif [[ -f "$HOME/.ssh/id_rsa.pub" ]]; then
    KEY_PATH="$HOME/.ssh/id_rsa.pub"
  elif [[ -f "$HOME/.ssh/id_ecdsa.pub" ]]; then
    KEY_PATH="$HOME/.ssh/id_ecdsa.pub"
  else
    # No public key found; generate a new ed25519 keypair (won't overwrite existing files)
    echo "No SSH keypair found in ~/.ssh; generating new ed25519 keypair at ~/.ssh/id_ed25519 ..."
    ssh-keygen -t ed25519 -N "" -f "$HOME/.ssh/id_ed25519" >/dev/null
    KEY_PATH="$HOME/.ssh/id_ed25519.pub"
  fi
  # Ensure reasonable permissions
  if [[ -f "$HOME/.ssh/id_ed25519" ]]; then
    chmod 600 "$HOME/.ssh/id_ed25519" || true
  fi
  if [[ -f "$KEY_PATH" ]]; then
    chmod 644 "$KEY_PATH" || true
  fi
fi

if [[ ! -f "$KEY_PATH" ]]; then
  echo "ERROR: Key path $KEY_PATH not found. Use --key-path to specify a valid public key."
  exit 2
fi

for h in "${HOSTS[@]}"; do
  user_to_use="${HOST_USER_MAP[$h]:-$TARGET_USER}"
  # fallback if still empty
  if [[ -z "$user_to_use" ]]; then user_to_use="root"; fi
  pw_to_use="${USER_TO_PASSWORD[$user_to_use]:-$SSH_PASS}"

  echo "Trusting host: $h (user: $user_to_use)"
  # Always remove existing entries for this host (handles IP reuse after VM recreation)
  echo "  Removing any existing SSH entries for $h..."
  ssh-keygen -R "$h" >/dev/null 2>&1 || true
  
  # Also remove by hostname if it exists in known_hosts 
  if [[ -f "$HOME/.ssh/known_hosts" ]]; then
    # Remove any lines containing this IP (handles different key formats)
    sed -i "/^$h\|,$h\|^.*$h /d" "$HOME/.ssh/known_hosts" 2>/dev/null || true
  fi
  
  # Fetch and trust fresh host key
  echo "  Adding fresh SSH host key for $h..."
  ssh-keyscan -H "$h" >> ~/.ssh/known_hosts 2>/dev/null || true
  chmod 600 ~/.ssh/known_hosts

  # Test login and push our public key (password-based initial auth)
  echo "Pushing SSH public key to $h for user ${user_to_use} ..."
  ATTEMPTS=0; MAX_ATTEMPTS=3; OK=0
  while [[ $ATTEMPTS -lt $MAX_ATTEMPTS ]]; do
    if sshpass -p "$pw_to_use" ssh -o PreferredAuthentications=password,keyboard-interactive -o PubkeyAuthentication=no -o StrictHostKeyChecking=no ${user_to_use}@"$h" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" < "$KEY_PATH"; then
      OK=1; break
    fi
    ATTEMPTS=$((ATTEMPTS+1))
    echo "Attempt $ATTEMPTS/$MAX_ATTEMPTS failed to push key to $h; retrying..."
    sleep 1
  done
  if [[ $OK -ne 1 ]]; then
    echo "Failed to push key to $h after $MAX_ATTEMPTS attempts."
  fi

  # Simple connectivity check with PATH set correctly for hostname command
  if ! ssh -o StrictHostKeyChecking=no ${user_to_use}@"$h" "PATH=/usr/bin:/bin:/usr/sbin:/sbin; echo 'SSH OK on '$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo 'remote-host')"; then
    echo -e "Hint: If authentication keeps failing, on the Proxmox host check /etc/ssh/sshd_config for:\n  PermitRootLogin yes (if using root)\n  PasswordAuthentication yes (only for the initial push)\nThen: systemctl restart ssh\nIf using 2FA for root, temporarily disable it or use a non-root user with --user."
  fi

  # Set up passwordless sudo for non-root users
  if [[ "$user_to_use" != "root" ]]; then
    echo "Setting up passwordless sudo for ${user_to_use} on $h..."
    SUDO_ATTEMPTS=0; SUDO_MAX=3; SUDO_OK=0
    escaped_pw=$(printf '%q' "$pw_to_use")
    while [[ $SUDO_ATTEMPTS -lt $SUDO_MAX ]]; do
  if sshpass -p "$pw_to_use" ssh -o StrictHostKeyChecking=no ${user_to_use}@"$h" "bash -s" <<EOSSH
set -euo pipefail
ASKPASS=\$(mktemp)
cat <<EOF > "\$ASKPASS"
#!/bin/sh
printf '%s\n' $escaped_pw
EOF
chmod 700 "\$ASKPASS"
SUDO_ASKPASS="\$ASKPASS" sudo -A bash <<'EOSUDO'
set -euo pipefail
tmp_file=\$(mktemp)
trap 'rm -f "\$tmp_file"' EXIT
rm -f /etc/sudoers.d/${user_to_use} /etc/sudoers.d/*-${user_to_use}-nopasswd 2>/dev/null || true
printf '%s\n' '${user_to_use} ALL=(ALL:ALL) NOPASSWD:ALL' > "\$tmp_file"
visudo -cf "\$tmp_file"
install -m 0440 "\$tmp_file" /etc/sudoers.d/${user_to_use}
EOSUDO
rm -f "\$ASKPASS"
EOSSH
  then
        SUDO_OK=1
        echo "  ✓ Passwordless sudo configured for ${user_to_use} on $h"
        break
      fi
      SUDO_ATTEMPTS=$((SUDO_ATTEMPTS+1))
      echo "  Attempt $SUDO_ATTEMPTS/$SUDO_MAX failed to configure sudo on $h; retrying..."
      sleep 1
    done
    if [[ $SUDO_OK -ne 1 ]]; then
      echo "  ✗ Failed to configure passwordless sudo on $h after $SUDO_MAX attempts."
      echo "    You may need to manually run: echo '${user_to_use} ALL=(ALL:ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/${user_to_use}"
    fi
  fi
done

echo "All hosts processed. Passwordless access should now work if keys were pushed."
