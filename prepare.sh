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

    echo -e "${YELLOW}Checking if group with GID=${GID} or name='${UNAME}' exists...${NC}"
    
    # Check if group with GID or name exists
    group_by_gid=$(getent group "${GID}" | cut -d: -f1)
    group_by_name=$(getent group "${UNAME}" | cut -d: -f3)

    if [ -n "${group_by_gid}" ] && [ "${group_by_gid}" != "${UNAME}" ]; then
        echo -e "${YELLOW}Group found with GID=${GID}: '${group_by_gid}'. Renaming to '${UNAME}'...${NC}"
        groupmod -n "${UNAME}" "${group_by_gid}"
    elif [ -n "${group_by_name}" ] && [ "${group_by_name}" != "${GID}" ]; then
        echo -e "${YELLOW}Group '${UNAME}' exists with different GID=${group_by_name}. Changing GID to ${GID}...${NC}"
        groupmod -g "${GID}" "${UNAME}"
    elif [ -z "${group_by_gid}" ] && [ -z "${group_by_name}" ]; then
        echo -e "${YELLOW}No existing group with GID=${GID} or name='${UNAME}'. Creating group...${NC}"
        groupadd -g "${GID}" "${UNAME}"
    else
        echo -e "${YELLOW}Group '${UNAME}' already exists with correct GID=${GID}. No changes needed.${NC}"
    fi

    echo -e "${YELLOW}Checking if user with UID=${UID} or name='${UNAME}' exists...${NC}"
    
    # Check if user with UID or name exists
    user_by_uid=$(getent passwd "${UID}" | cut -d: -f1)
    user_by_name=$(getent passwd "${UNAME}" | cut -d: -f3)

    if [ -n "${user_by_uid}" ] && [ "${user_by_uid}" != "${UNAME}" ]; then
        echo -e "${YELLOW}User found with UID=${UID}: '${user_by_uid}'. Renaming to '${UNAME}'...${NC}"
        usermod -l "${UNAME}" "${user_by_uid}"
        usermod -d "/home/${UNAME}" -m "${UNAME}"
    elif [ -n "${user_by_name}" ] && [ "${user_by_name}" != "${UID}" ]; then
        echo -e "${YELLOW}User '${UNAME}' exists with different UID=${user_by_name}. Changing UID to ${UID}...${NC}"
        usermod -u "${UID}" -d "/home/${UNAME}" -m "${UNAME}"
    elif [ -z "${user_by_uid}" ] && [ -z "${user_by_name}" ]; then
        echo -e "${YELLOW}No existing user with UID=${UID} or name='${UNAME}'. Creating user...${NC}"
        useradd -u "${UID}" -g "${GID}" -m "${UNAME}"
    else
        echo -e "${YELLOW}User '${UNAME}' already exists with correct UID=${UID}. No changes needed.${NC}"
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
