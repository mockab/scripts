#!/bin/bash

# Function to check if rsyslog is installed and install if missing
check_rsyslog_installed() {
  if ! command -v rsyslogd >/dev/null 2>&1; then
    echo "rsyslog is not installed. Installing..."

    # Check if it's an RHEL-based system
    if [ -f /etc/redhat-release ]; then
      if command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y rsyslog
      else
        sudo yum install -y rsyslog
      fi
    # Check if it's a Debian-based system
    elif [ -f /etc/debian_version ]; then
      sudo apt update && sudo apt install -y rsyslog
    else
      echo "Unsupported distribution. Please install rsyslog manually."
      exit 1
    fi
  else
    echo "rsyslog is already installed."
  fi
}

# Function to prompt for the remote host address
get_remote_host() {
  read -p "Enter the remote syslog IP or hostname: " remote_host
  if [[ -z "$remote_host" ]]; then
    echo "Remote host cannot be empty. Please run the script again and provide a valid host."
    exit 1
  fi
}

# Function to configure rsyslog for TCP forwarding
configure_rsyslog() {
  local remote_host=$1

  # Backup existing rsyslog.conf file
  echo "Backing up current rsyslog configuration..."
  sudo cp /etc/rsyslog.conf /etc/rsyslog.conf.bak

  # Check if TCP forwarding is already configured
  if grep -q "@@$remote_host" /etc/rsyslog.conf; then
    echo "TCP logging to $remote_host is already configured."
  else
    # Add TCP logging configuration
    echo "Configuring rsyslog to forward logs to $remote_host over TCP..."
    echo "*.*  @@$remote_host:514" | sudo tee -a /etc/rsyslog.conf
  fi

  # Enable and start the rsyslog service
  echo "Restarting rsyslog service..."
  if systemctl is-active rsyslog >/dev/null 2>&1; then
    sudo systemctl restart rsyslog
  else
    sudo systemctl enable rsyslog --now
  fi

  # Check if the service restarted successfully
  if systemctl is-active --quiet rsyslog; then
    echo "rsyslog is successfully forwarding logs to $remote_host over TCP."
  else
    echo "There was an issue restarting rsyslog. Please check the configuration."
  fi
}

# Main script
echo "=== rsyslog Configuration Script ==="

# Step 1: Check if rsyslog is installed
check_rsyslog_installed

# Step 2: Prompt user for remote host
get_remote_host

# Step 3: Configure rsyslog
configure_rsyslog "$remote_host"
