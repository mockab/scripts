#!/bin/bash

# Function to handle errors
error_exit() {
    echo "Error: $1"
    exit $2
}

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
    error_exit "This script must be run as root." 1
fi

# Install dependencies
install_dependencies() {
    if [ -f /etc/redhat-release ]; then
        echo "Detected Red Hat-based system. Installing dependencies..."
        yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm || error_exit "Failed to install EPEL repository." 2
        yum install -y figlet || error_exit "Failed to install figlet." 3
    elif [ -f /etc/lsb-release ] || [ -f /etc/os-release ]; then
        . /etc/os-release
        if [[ "$ID" == "ubuntu" || "$ID" == "debian" ]]; then
            echo "Detected Ubuntu-based system. Installing dependencies..."
            apt-get update || error_exit "Failed to update package list." 4
            apt-get install -y figlet || error_exit "Failed to install figlet." 5
        else
            error_exit "Unsupported Debian-based system." 6
        fi
    else
        error_exit "Unsupported operating system." 7
    fi
}

# Create the MOTD script
create_motd_script() {
    cat << 'EOF' > /etc/update-motd.d/99-custom
#!/bin/sh
if [[ $- == *i* ]]; then
    #
    if [ -r /etc/lsb-release ]; then
        . /etc/lsb-release
    elif [ -r /etc/os-release ]; then
        . /etc/os-release
        DISTRIB_DESCRIPTION=$PRETTY_NAME
    fi

    if [ -z "$DISTRIB_DESCRIPTION" ] && [ -x /usr/bin/lsb_release ]; then
        # Fall back to using the very slow lsb_release utility
        DISTRIB_DESCRIPTION=$(lsb_release -s -d)
    fi

    figlet "$(hostname -s).$(hostname -d | cut -d '.' -f1)"
    printf "\n"

    if [ -f /etc/redhat-release ]; then
        OS_INFO=$(cat /etc/redhat-release)
    else
        OS_INFO=$DISTRIB_DESCRIPTION
    fi

    printf "Welcome to %s (%s).\n" "$DISTRIB_DESCRIPTION" "$OS_INFO"
    printf "\n"

    # System date
    date=$(date)

    # System load
    LOAD1=$(cat /proc/loadavg | awk '{print $1}')
    LOAD5=$(cat /proc/loadavg | awk '{print $2}')
    LOAD15=$(cat /proc/loadavg | awk '{print $3}')

    # System uptime
    uptime=$(cat /proc/uptime | cut -f1 -d.)
    upDays=$((uptime/60/60/24))
    upHours=$((uptime/60/60%24))
    upMins=$((uptime/60%60))

    # Root fs info
    root_usage=$(df -h / | awk '/\// {print $4}' | grep -v "^$")
    fsperm=$(mount | grep " on / " | awk '{print $6}' | awk -F"," '{print $1}')

    # Memory Usage
    memory_usage=$(free -m | awk '/Mem:/ { total=$2 } /Mem:/ { used=$3 } END { printf("%3.1f%%", used/total*100)}')
    swap_usage=$(free -m | awk '/Swap/ { printf("%3.1f%%", $3/$2*100) }')

    # Users
    users=$(users | wc -w)
    USER=$(whoami)

    # Processes
    processes=$(ps aux | wc -l)

    # Interfaces
    INTERFACE=$(ip -4 ad | grep 'state UP' | awk -F ":" '!/^[0-9]*: ?lo/ {print $2}')

    echo "System information as of: $date"
    echo
    printf "System Load:\t%s %s %s\tSystem Uptime:\t\t%s days %s hours %s min\n" $LOAD1 $LOAD5 $LOAD15 $upDays $upHours $upMins
    printf "Memory Usage:\t%s\t\t\tSwap Usage:\t\t%s\n" $memory_usage $swap_usage
    printf "Usage On /:\t%s\t\t\tAccess Rights on /:\t%s\n" $root_usage $fsperm
    printf "Local Users:\t%s\t\t\tWhoami:\t\t\t%s\n" $users $USER
    printf "Processes:\t%s\t\t\t\n" $processes
    printf "\n"
    printf "Interface\tMAC Address\t\tIP Address\t\n"

    for x in $INTERFACE; do
        MAC=$(ip ad show dev $x | grep link/ether | awk '{print $2}')
        IP=$(ip ad show dev $x | grep -v inet6 | grep inet | awk '{print $2}')
        printf "%s\t\t%s\t%s\t\n" $x $MAC $IP
    done

    echo
fi
EOF
    chmod +x /etc/update-motd.d/99-custom || error_exit "Failed to make the MOTD script executable." 8
}

# Main function
main() {
    install_dependencies
    create_motd_script
    echo "MOTD script successfully installed and configured."
}

main
