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

    echo -e "${YELLOW}Checking if group with GID=${GID} exists...${NC}"
    # Rename group and create if necessary
    group=$(getent group "${GID}" | cut -d: -f1)
    if [ -n "${group}" ] && [ "${group}" != "${UNAME}" ]; then
        echo -e "${YELLOW}Group found: '${group}' with GID=${GID}. Renaming to '${UNAME}'...${NC}"
        groupmod -n "${UNAME}" "${group}"
    else
        echo -e "${YELLOW}No existing group with GID=${GID}. Creating group '${UNAME}'...${NC}"
        groupadd -g "${GID}" "${UNAME}"
    fi
    
    echo -e "${YELLOW}Checking if user with UID=${UID} exists...${NC}"
    # Rename user and create if necessary
    user=$(getent passwd "${UID}" | cut -d: -f1)
    if [ -n "${user}" ]; then
        if [ "${user}" != "${UNAME}" ]; then
            echo -e "${YELLOW}User found: '${user}' with UID=${UID}. Renaming to '${UNAME}'...${NC}"
            usermod -l "${UNAME}" "${user}"
            usermod -d "/home/${UNAME}" -m "${UNAME}"
        else
            echo -e "${YELLOW}User '${UNAME}' already exists with correct UID=${UID}. No changes needed.${NC}"
        fi
    else
        echo -e "${YELLOW}No existing user with UID=${UID}. Creating user '${UNAME}'...${NC}"
        useradd -u "${UID}" -g "${GID}" -m "${UNAME}"
    fi

    echo -e "${GREEN}Setting ownership for ${UNAME}...${NC}"
    mkdir -p "/mnt/files"
    chown "${UID}:${GID}" "/mnt/files" "/opt/packages/server"
    echo -e "${GREEN}Ownership set successfully for ${UNAME}!${NC}"
}

if [ "$(id -u)" -eq 0 ]; then
    echo -e "${GREEN}Script running as root. Starting setup...${NC}"
    setup_user  # Call the setup_user function
    echo -e "${GREEN}Switching to user '${UNAME}' to execute command...${NC}"
    exec gosu "${UNAME}" "$@"  # Switch to the specified user
else
    echo -e "${YELLOW}Script not running as root. Executing command directly...${NC}"
    exec "$@"  # If not root, execute the command directly
fi
