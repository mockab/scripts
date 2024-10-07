#!/bin/bash

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root or with sudo privileges" 
   exit 1
fi

# Get the system's own IP address (assuming it's on eth0 or a similar interface)
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

# Run the commands
echo "Installing Zabbix repository..."
rpm -Uvh https://repo.zabbix.com/zabbix/6.0/rhel/8/x86_64/zabbix-release-6.0-5.el8.noarch.rpm

echo "Cleaning DNF cache..."
dnf clean all

echo "Installing Zabbix Agent 2 and plugins..."
dnf install -y zabbix-agent2 zabbix-agent2-plugin-*

# Start and enable Zabbix Agent 2 before updating the config
echo "Restarting and enabling Zabbix Agent 2..."
systemctl restart zabbix-agent2
systemctl enable zabbix-agent2

# Update the Zabbix Agent 2 configuration
echo "Updating Zabbix Agent 2 configuration..."
sed -i "s/Server=127.0.0.1/Server=${zabbix_ip}/" /etc/zabbix/zabbix_agent2
sed -i "s/ServerActive=127.0.0.1/ServerActive=${zabbix_ip}/" /etc/zabbix/zabbix_agent2
sed -i "s/Hostname=Zabbix server/Hostname=$(hostname)/" /etc/zabbix/zabbix_agent2

# Get the hostname of the server
current_hostname=$(hostname)

# Check if the hostname contains "splk"
if [[ "$current_hostname" == *"splk"* ]]; then
    echo "Hostname contains 'splk', using Splunk firewall zone configuration..."
    firewall-cmd --permanent --zone=splunk --add-port=10050/tcp
else
    echo "Hostname does not contain 'splk', using Zabbix-specific firewall zone configuration..."
    firewall-cmd --new-zone=zabbix --permanent
    firewall-cmd --permanent --zone=zabbix --add-source=${zabbix_ip}/32
    firewall-cmd --permanent --zone=zabbix --add-port=10050/tcp
fi

# Reload the firewall to apply changes
firewall-cmd --reload

# Restart Zabbix Agent 2 to apply the new configuration
echo "Restarting Zabbix Agent 2..."
systemctl restart zabbix-agent2

echo "Zabbix Agent 2 installation and configuration complete."
