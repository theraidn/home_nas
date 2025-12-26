#!/bin/bash
set -e

# --- Source function scripts and configuration ---
# The following scripts are sourced to make their functions available.
# They are expected to be in a 'scripts' subdirectory relative to this script.
source "$(dirname "$0")/config.sh"
source "$(dirname "$0")/scripts/get_user_input.sh"
source "$(dirname "$0")/scripts/remote_script.sh"

# --- Functions ---

#
# Executes the deployment script on the remote NAS via SSH.
#
deploy_to_nas() {
    echo
    echo "Starting remote setup on $SSH_TARGET. You may be prompted for the SSH password."
    echo "This will take several minutes."
    echo

    # The generate_remote_script function prints the script to stdout. We pipe this
    # to ssh, which executes it on the remote host using "bash -s".
    # This avoids creating a temporary script file and is more secure than
    # passing passwords as command-line arguments.
    generate_remote_script | ssh -t "$SSH_TARGET" "bash -s"
}

# --- Main Script ---
main() {
    echo "### NAS Initial Deployment Script ###"
    echo

    # Get any missing configuration from the user
    get_user_input

    # The deploy_to_nas function uses the variables from config.sh and get_user_input
    deploy_to_nas

    echo
    echo "### Local Script Finished ###"
}

# Run the main function
main