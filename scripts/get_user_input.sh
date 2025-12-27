#!/bin/bash

#
# Prompts user for necessary inputs like username and passwords if they are not
# already set in the config.sh file.
# This script should be sourced by the main script.
#
get_user_input() {
    if [ -z "$SSH_TARGET" ]; then
        read -p "Enter the SSH connection details (e.g., user@host): " SSH_TARGET
        if [ -z "$SSH_TARGET" ]; then
            echo "SSH_TARGET is required. Exiting."
            exit 1
        fi
    fi

    if [ -z "$NAS_USER" ]; then
        read -p "Enter the username for the new NAS user [nas_user]: " NAS_USER
        NAS_USER=${NAS_USER:-nas_user}
    fi

    if [ -z "$NAS_USER_PASSWORD" ]; then
        while true; do
            read -s -p "Enter a secure password for user '$NAS_USER': " NAS_USER_PASSWORD
            echo
            read -s -p "Confirm password: " NAS_USER_PASSWORD_CONFIRM
            echo
            [ "$NAS_USER_PASSWORD" = "$NAS_USER_PASSWORD_CONFIRM" ] && break
            echo "Passwords do not match. Please try again."
        done
    fi

    if [ -z "$GOCRYPTFS_PASSWORD" ]; then
        while true; do
            read -s -p "Enter a secure password for the encrypted NAS data: " GOCRYPTFS_PASSWORD
            echo
            read -s -p "Confirm password: " GOCRYPTFS_PASSWORD_CONFIRM
            echo
            [ "$GOCRYPTFS_PASSWORD" = "$GOCRYPTFS_PASSWORD_CONFIRM" ] && break
            echo "Passwords do not match. Please try again."
        done
    fi
}