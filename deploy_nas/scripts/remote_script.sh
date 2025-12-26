#!/bin/bash

#
# Generates the shell script that will be executed on the remote NAS.
# This script should be sourced by the main script.
#
generate_remote_script() {
    # Define paths, using defaults if not provided in config.sh
    NAS_HOME_DIR="/home/$NAS_USER"
    FINAL_ENCRYPTED_DATA_DIR=${ENCRYPTED_DATA_DIR:-"$NAS_HOME_DIR/nas_encrypted"}
    FINAL_DECRYPTED_MOUNT_POINT=${DECRYPTED_MOUNT_POINT:-"$NAS_HOME_DIR/NAS"}

    # Prepare package installation commands
    local syncthing_pkg="syncthing"
    if [ -n "$SYNCTHING_VERSION" ]; then
        syncthing_pkg="syncthing=${SYNCTHING_VERSION}"
    fi

    local gocryptfs_pkg="gocryptfs"
    if [ -n "$GOCRYPTFS_VERSION" ]; then
        gocryptfs_pkg="gocryptfs=${GOCRYPTFS_VERSION}"
    fi

    # Using a HEREDOC to create the remote script content
    cat <<EOF
set -e

echo "--- (REMOTE) Updating OS package list... ---"
sudo apt-get update

if [ "$PERFORM_SYSTEM_UPGRADE" = "true" ]; then
    echo "--- (REMOTE) Performing full system upgrade... ---"
    sudo apt-get upgrade -y
fi

echo "--- (REMOTE) Installing prerequisites... ---"
sudo apt-get install -y curl gpg

echo "--- (REMOTE) Adding Syncthing repository... ---"
sudo curl -s -o /usr/share/keyrings/syncthing-archive-keyring.gpg https://syncthing.net/release-key.gpg
echo "deb [signed-by=/usr/share/keyrings/syncthing-archive-keyring.gpg] https://apt.syncthing.net/ syncthing stable" | sudo tee /etc/apt/sources.list.d/syncthing.list

echo "--- (REMOTE) Updating repositories and installing Syncthing + gocryptfs... ---"
sudo apt-get update
sudo apt-get install -y ${syncthing_pkg} ${gocryptfs_pkg}

echo "--- (REMOTE) Checking for NAS user: ${NAS_USER}... ---"
if id -u "${NAS_USER}" >/dev/null 2>&1; then
    echo "User '${NAS_USER}' already exists. Skipping creation."
else
    echo "Creating user '${NAS_USER}'..."
    sudo useradd -m -s /bin/bash "${NAS_USER}"
    echo "${NAS_USER}:${NAS_USER_PASSWORD}" | sudo chpasswd
    echo "User ${NAS_USER} created."
fi

echo "--- (REMOTE) Configuring SFTP access for ${NAS_USER}... ---"
if sudo grep -q "^Match User ${NAS_USER}$" /etc/ssh/sshd_config; then
    echo "SFTP configuration for ${NAS_USER} already exists in /etc/ssh/sshd_config. Skipping."
else
    echo "Adding SFTP configuration for ${NAS_USER} to /etc/ssh/sshd_config."
    sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    sudo bash -c 'cat >> /etc/ssh/sshd_config' <<EOT

# SFTP chroot jail for the NAS user
Match User ${NAS_USER}
    ChrootDirectory %h
    ForceCommand internal-sftp
    AllowTcpForwarding no
    X11Forwarding no
EOT
fi

echo "--- (REMOTE) Restarting SSH service... ---"
sudo systemctl restart sshd

echo "--- (REMOTE) Creating NAS data directories... ---"
sudo -u "${NAS_USER}" mkdir -p "${FINAL_ENCRYPTED_DATA_DIR}"
sudo -u "${NAS_USER}" mkdir -p "${FINAL_DECRYPTED_MOUNT_POINT}"
echo "Directories created:"
echo "Encrypted storage: ${FINAL_ENCRYPTED_DATA_DIR}"
echo "Decrypted mount point: ${FINAL_DECRYPTED_MOUNT_POINT}"

echo "--- (REMOTE) Initializing gocryptfs encrypted directory... ---"
if [ -f "${FINAL_ENCRYPTED_DATA_DIR}/gocryptfs.conf" ]; then
    echo "gocryptfs directory already initialized. Skipping."
else
    # Check if the directory is empty
    if [ "$(ls -A "${FINAL_ENCRYPTED_DATA_DIR}")" ]; then
        echo "WARNING: Encrypted directory ${FINAL_ENCRYPTED_DATA_DIR} is not empty but not initialized."
        read -p "Do you want to continue and initialize it anyway? This might lead to errors. (y/N): " choice
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            echo "Proceeding with initialization..."
            echo "${GOCRYPTFS_PASSWORD}" | sudo -u "${NAS_USER}" gocryptfs -init "${FINAL_ENCRYPTED_DATA_DIR}"
        else
            echo "Skipping gocryptfs initialization."
        fi
    else
        # Directory is empty, so initialize it.
        echo "Initializing empty directory..."
        echo "${GOCRYPTFS_PASSWORD}" | sudo -u "${NAS_USER}" gocryptfs -init "${FINAL_ENCRYPTED_DATA_DIR}"
    fi
fi

echo "--- (REMOTE) Enabling Syncthing to run on boot for ${NAS_USER}... ---"
sudo systemctl enable syncthing@"${NAS_USER}".service

echo "--- (REMOTE) Creating /start.sh script on the NAS... ---"
sudo bash -c 'cat > /start.sh' <<'EOT'
#!/bin/bash
set -e
NAS_USER="##NAS_USER##"
ENCRYPTED_DIR="##ENCRYPTED_DIR##"
DECRYPTED_DIR="##DECRYPTED_DIR##"

echo "### NAS Start Script ###"
if mount | grep -q "on \${DECRYPTED_DIR} type fuse.gocryptfs"; then
    echo "NAS is already decrypted and mounted at \${DECRYPTED_DIR}."
else
    read -s -p "Enter password to decrypt NAS data: " GOCRYPTFS_PASSWORD
    echo
    echo "Mounting encrypted directory..."
    echo "\$GOCRYPTFS_PASSWORD" | sudo -u "\$NAS_USER" gocryptfs "\$ENCRYPTED_DIR" "\$DECRYPTED_DIR"
    echo "Mount successful."
fi

echo "Starting Syncthing service for user \$NAS_USER..."
if ! sudo systemctl is-active --quiet syncthing@"\$NAS_USER".service; then
    sudo systemctl start syncthing@"\$NAS_USER".service
    echo "Syncthing service started."
else
    echo "Syncthing service is already running."
fi

echo
echo "NAS is ready. Access your files at: \${DECRYPTED_DIR}"
echo "Syncthing Web UI is available at: http://127.0.0.1:8384 (use SSH port forwarding to access)"
EOT

sudo sed -i "s|##NAS_USER##|${NAS_USER}|g" /start.sh
sudo sed -i "s|##ENCRYPTED_DIR##|${FINAL_ENCRYPTED_DATA_DIR}|g" /start.sh
sudo sed -i "s|##DECRYPTED_DIR##|${FINAL_DECRYPTED_MOUNT_POINT}|g" /start.sh
sudo chmod +x /start.sh

echo
echo "--- (REMOTE) DEPLOYMENT COMPLETE ---"
echo "The initial setup on the NAS is finished."
echo "A script has been created at /start.sh on the NAS."
echo "After you reboot the NAS, you must log in and run 'sudo /start.sh' to decrypt the data drive and start Syncthing."
EOF
}