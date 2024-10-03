#!/bin/bash
set -e

# Define colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

setup_user() {
    UID="${UID:-1000}"
    GID="${GID:-1000}"
    UNAME="${USERNAME:-containerdx}"

    # Rename group and create if necessary
    group=$(getent group "${GID}" | cut -d: -f1)
    if [ -n "${group}" ] && [ "${group}" != "${UNAME}" ]; then
        groupmod -n "${UNAME}" "${group}"
    else
        groupadd -g "${GID}" "${UNAME}"
    fi
    
    # Rename user and create if necessary
    user=$(getent passwd "${UID}" | cut -d: -f1)
    if [ -n "${user}" ]; then
        if [ "${user}" != "${UNAME}" ]; then
            usermod -l "${UNAME}" "${user}"
            usermod -d "/home/${UNAME}" "${UNAME}"
            
            if [ -d "/home/${user}" ]; then
                mv "/home/${user}" "/home/${UNAME}" || { echo "Failed to rename home directory"; exit 1; }
            else
                echo "Home directory for ${user} does not exist"
            fi
        fi
    else
        useradd -u "${UID}" -g "${GID}" -m "${UNAME}"
    fi

    # Set ownership of the home directory
    echo -e "${GREEN}Setting ownership of home directory for ${UNAME}...${NC}"
    mkdir -p "/home/${UNAME}"
    mkdir -p "/mnt/files"
    chown "${UID}:${GID}" "/home/${UNAME}" "/mnt/files"
    echo -e "${GREEN}Ownership set successfully for ${UNAME}!${NC}"
}

if [ "$(id -u)" -eq 0 ]; then
    echo -e "${GREEN}Hold tight!${NC}"
    setup_user  # Call the setup_user function
    cd /home/${UNAME}/packages/server
    exec gosu "${UNAME}" "$@"  # Switch to the specified user
else
    cd /home/node/packages/server
    exec "$@"  # If not root, execute the command directly
fi