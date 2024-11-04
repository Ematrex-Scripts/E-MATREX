#!/bin/bash

PORT_PROXY="$1"
USERNAME="$2"
PASSWORD="$3"

if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    echo "Operating system not supported."
    exit 1
fi

echo "Detected OS: $OS"
echo "Detected Version: $VER"

install_and_configure_squid() {
    echo "Installing Squid..."
    if [[ "$OS" == "ubuntu" ]]; then
        apt-get update -y
        apt-get install -y squid apache2-utils
    else
        if [[ "$VER" == "7" ]]; then
            yum install -y squid httpd-tools
        else
            dnf install -y squid httpd-tools
        fi
    fi

    if ! command -v squid >/dev/null; then
        echo "Squid installation failed."
        exit 1
    fi

    AUTH_HELPER=$(find /usr/lib* -name basic_ncsa_auth)
    if [ -z "$AUTH_HELPER" ]; then
        echo "basic_ncsa_auth not found."
        exit 1
    fi
    echo "Using authentication helper at: $AUTH_HELPER"

    if [ -f /etc/squid/squid.conf ]; then
        cp /etc/squid/squid.conf /etc/squid/squid.conf.bak
    fi

    htpasswd -b -c /etc/squid/squid_passwd "$USERNAME" "$PASSWORD"

    cat << EOF > /etc/squid/squid.conf
auth_param basic program $AUTH_HELPER /etc/squid/squid_passwd
auth_param basic children 5
auth_param basic realm Proxy Server
auth_param basic credentialsttl 2 hours
auth_param basic casesensitive on

acl authenticated_users proxy_auth REQUIRED
http_access allow authenticated_users
http_access deny all

forwarded_for delete
http_port 0.0.0.0:$PORT_PROXY

cache deny all
access_log /var/log/squid/access.log

request_body_max_size 10 MB
read_timeout 15 minutes
request_timeout 15 minutes

via off
EOF

    echo "Verifying Squid configuration..."
    squid -k parse
    if [ $? -ne 0 ]; then
        echo "Squid configuration has errors."
        exit 1
    fi

    echo "Restarting Squid..."
    systemctl restart squid
    systemctl enable squid
    echo "Squid installation and configuration complete."
}

case $OS in
    "ubuntu")
        install_and_configure_squid
        ;;
    "centos" | "almalinux" | "rocky")
        install_and_configure_squid
        ;;
    *)
        echo "Unsupported operating system."
        exit 1
        ;;
esac

if systemctl is-active --quiet squid; then
    echo "Squid is running successfully on port $PORT_PROXY."
else
    echo "Squid failed to start. Check the configuration or logs for errors."
    exit 1
fi
