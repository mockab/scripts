#!/bin/bash

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root or with sudo privileges"
   exit 1
fi

# Check if a Zabbix endpoint is provided as an argument
if [ -z "$1" ]; then
    echo "No Zabbix endpoint provided, deriving IP based on system's network configuration..."

    # Get the system's own IP address
    system_ip=$(hostname -I | awk '{print $1}')

    # Extract the second octet from the system's IP address
    second_octet=$(echo "$system_ip" | cut -d '.' -f 2)

    # Validate the second octet
    if ! [[ "$second_octet" =~ ^[0-9]+$ ]] || [ "$second_octet" -lt 0 ] || [ "$second_octet" -gt 255 ]; then
        echo "Failed to extract a valid second octet from the IP address."
        exit 1
    fi

    # Construct the full Zabbix server IP address (assuming a 10.X.30.1 format)
    zabbix_ip="10.${second_octet}.30.1"
else
    # Use the provided argument as the Zabbix endpoint (IP or hostname)
    zabbix_ip="$1"
    echo "Using provided Zabbix endpoint: ${zabbix_ip}"
fi

# Detect OS and install Zabbix Agent accordingly
if [ -f /etc/redhat-release ]; then
    echo "Detected RHEL-based system."
    echo "Installing Zabbix repository..."
    rpm -Uvh https://repo.zabbix.com/zabbix/6.0/rhel/8/x86_64/zabbix-release-6.0-5.el8.noarch.rpm

    echo "Cleaning DNF cache..."
    dnf clean all

    echo "Installing Zabbix Agent 2 and plugins..."
    dnf install -y zabbix-agent2 zabbix-agent2-plugin-*

elif [ -f /etc/lsb-release ]; then
    echo "Detected Ubuntu-based system."

    # Detect architecture
    ARCH=$(dpkg --print-architecture)
    if [ "$ARCH" == "amd64" ]; then
        echo "Detected x86_64 architecture."
        echo "Installing Zabbix repository for x86_64..."
        wget https://repo.zabbix.com/zabbix/6.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_6.0-4+ubuntu22.04_all.deb
	dpkg -i zabbix-release_6.0-4+ubuntu22.04_all.deb
    elif [ "$ARCH" == "arm64" ]; then
        echo "Detected arm64 architecture."
        echo "Installing Zabbix repository for arm64..."
        wget https://repo.zabbix.com/zabbix/6.0/ubuntu-arm64/pool/main/z/zabbix-release/zabbix-release_6.0-5+ubuntu22.04_all.deb
	dpkg -i zabbix-release_6.0-5+ubuntu22.04_all.deb
    else
        echo "Unsupported architecture for Ubuntu."
        exit 1
    fi

    echo "Updating package list..."
    apt update

    echo "Installing Zabbix Agent 2..."
    apt install -y zabbix-agent2

elif [ -f /etc/debian_version ]; then
    echo "Detected Debian-based system."

    # Detect architecture
    ARCH=$(dpkg --print-architecture)
    if [ "$ARCH" == "amd64" ]; then
        echo "Detected x86_64 architecture."
        echo "Installing Zabbix repository for x86_64..."
        wget https://repo.zabbix.com/zabbix/7.0/debian/pool/main/z/zabbix-release/zabbix-release_latest+debian12_all.deb
	dpkg -i zabbix-release_latest+debian12_all.deb
    elif [ "$ARCH" == "arm64" ]; then
        echo "Detected arm64 architecture."
        echo "Installing Zabbix repository for arm64..."
        wget https://repo.zabbix.com/zabbix/7.0/debian-arm64/pool/main/z/zabbix-release/zabbix-release_latest+debian12_all.deb
	dpkg -i zabbix-release_latest+debian12_all.deb
    else
        echo "Unsupported architecture for Debian."
        exit 1
    fi

    echo "Updating package list..."
    apt update

    echo "Installing Zabbix Agent 2..."
    apt install -y zabbix-agent2
    
else
    echo "Unsupported OS. This script only supports RHEL-based and Ubuntu-based systems."
    exit 1
fi

# Start and enable Zabbix Agent 2 before updating the config
echo "Restarting and enabling Zabbix Agent 2..."
systemctl restart zabbix-agent2
systemctl enable zabbix-agent2

# Update the Zabbix Agent 2 configuration
echo "Updating Zabbix Agent 2 configuration..."
sed -i "s/Server=127.0.0.1/Server=${zabbix_ip}/" /etc/zabbix/zabbix_agent2.conf
sed -i "s/ServerActive=127.0.0.1/ServerActive=${zabbix_ip}/" /etc/zabbix/zabbix_agent2.conf
sed -i "s/Hostname=Zabbix server/Hostname=$(hostname)/" /etc/zabbix/zabbix_agent2.conf

# Get the hostname of the server
current_hostname=$(hostname)

# Configure the firewall based on hostname
if [[ "$current_hostname" == *"splk"* ]]; then
    echo "Hostname contains 'splk', using Splunk firewall zone configuration..."
    if command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --zone=splunk --add-port=10050/tcp
    elif command -v ufw &> /dev/null; then
        ufw allow 10050/tcp
    fi
else
    echo "Hostname does not contain 'splk', configuring Zabbix-specific firewall rules..."
    if command -v firewall-cmd &> /dev/null; then
        firewall-cmd --new-zone=zabbix --permanent
        firewall-cmd --permanent --zone=zabbix --add-source=${zabbix_ip}/32
        firewall-cmd --permanent --zone=zabbix --add-port=10050/tcp
    elif command -v ufw &> /dev/null; then
	ufw allow from ${zabbix_ip} to any port 10050 proto tcp
    fi
fi

# Reload the firewall to apply changes if applicable
if command -v firewall-cmd &> /dev/null; then
    firewall-cmd --reload
elif command -v ufw &> /dev/null; then
    ufw reload
fi

# Restart Zabbix Agent 2 to apply the new configuration
echo "Restarting Zabbix Agent 2..."
systemctl restart zabbix-agent2

echo "Zabbix Agent 2 installation and configuration complete."
