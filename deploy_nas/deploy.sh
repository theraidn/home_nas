#!/bin/bash
set -e

# --- Source function scripts and configuration ---
# The following scripts are sourced to make their functions available.
# They are expected to be in a 'scripts' subdirectory relative to this script.
source "$(dirname "$0")/config.sh"
source "$(dirname "$0")/scripts/get_user_input.sh"

# --- Functions ---

#
# Generates the start.sh script from a template and configuration variables.
#
generate_start_script() {
    local template_path
    template_path="$(dirname "$0")/scripts/start.sh.template"
    local temp_script_path="/tmp/start.sh"

    # Define paths, using defaults if not provided in config.sh
    NAS_HOME_DIR="/home/$NAS_USER"
    FINAL_ENCRYPTED_DATA_DIR=${ENCRYPTED_DATA_DIR:-"$NAS_HOME_DIR/nas_encrypted"}
    FINAL_DECRYPTED_MOUNT_POINT=${DECRYPTED_MOUNT_POINT:-"$NAS_HOME_DIR/NAS"}

    echo "Generating start.sh from template..."
    sed -e "s|##NAS_USER##|${NAS_USER}|g" \
        -e "s|##ENCRYPTED_DIR##|${FINAL_ENCRYPTED_DATA_DIR}|g" \
        -e "s|##DECRYPTED_DIR##|${FINAL_DECRYPTED_MOUNT_POINT}|g" \
        "$template_path" > "$temp_script_path"
    
    echo "Generated start.sh at $temp_script_path"
}

#
# Executes the deployment script on the remote NAS via SSH.
#
deploy_to_nas() {
    # Source the remote script functions just before use
    source "$(dirname "$0")/scripts/remote_script.sh"

    echo
    echo "Starting remote setup on $SSH_TARGET. You may be prompted for the SSH password."
    echo "This will take several minutes."
    echo

    # Ensure local temporary script is cleaned up
    trap 'rm -f /tmp/start.sh' EXIT

    # Generate start.sh locally
    generate_start_script

    echo "Copying start.sh to remote /start.sh..."
    scp /tmp/start.sh "$SSH_TARGET:/start.sh"
    ssh -t "$SSH_TARGET" "chmod +x /start.sh"
    echo "start.sh copied and made executable."

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