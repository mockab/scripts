#!/bin/bash

# Function to prompt for input
prompt() {
    local varname=$1
    local prompt=$2
    local value
    read -p "$prompt: " value
    eval $varname="'$value'"
}

# Function to install packages based on the OS
install_packages() {
    if [ -f /etc/redhat-release ]; then
        sudo yum install -y realmd sssd oddjob oddjob-mkhomedir adcli samba-common samba-common-tools
    elif [ -f /etc/lsb-release ]; then
        sudo apt-get update
        sudo apt-get install -y realmd sssd sssd-tools libnss-sss libpam-sss adcli samba-common-bin oddjob oddjob-mkhomedir packagekit
    else
        echo "Unsupported OS"
        exit 1
    fi
}

# Prompt for credentials
prompt DOMAIN "Enter the domain (e.g., moskal.org)"
prompt USERNAME "Enter your domain username"
read -s -p "Enter your domain password: " PASSWORD
echo

# Install necessary packages
echo "Installing necessary packages..."
install_packages

# Discover the domain
echo "Discovering the domain..."
sudo realm discover $DOMAIN

# Join the domain
echo "Joining the domain..."
echo $PASSWORD | sudo realm join --user=$USERNAME $DOMAIN

# Configure SSSD to create home directories
echo "Configuring SSSD to create home directories..."
sudo bash -c 'echo "session required pam_mkhomedir.so skel=/etc/skel/ umask=0077" >> /etc/pam.d/common-session'

# Allow SG-linux_admins group to login
echo "Allowing SG-linux_admins group to login..."
sudo realm permit -g sg-linux_admins

# Configure sudoers to allow SG-linux_admins to use sudo without a password
echo "Configuring sudoers..."
sudo bash -c 'echo "%SG-linux_admins ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/SG-linux_admins'

# Set use_fully_qualified_names to false
echo "Setting FQDN to false"
sudo sed -i 's/use_fully_qualified_names = .*/use_fully_qualified_names = false/' /etc/sssd/sssd.conf

# Change fallback_homedir
echo "Setting fallback dir"
sudo sed -i 's/fallback_homedir = .*/fallback_homedir = \/home\/%u/' /etc/sssd/sssd.conf

# Restart SSSD service
echo "Restarting SSSD service..."
sudo systemctl restart sssd

echo "Successfully joined the domain $DOMAIN and configured SG-linux_admins group."
