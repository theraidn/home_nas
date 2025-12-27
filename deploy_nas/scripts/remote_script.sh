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

if [ \$(id -u) -ne 0 ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

echo "--- (REMOTE) Updating OS package list... ---"
apt-get update

if [ "$PERFORM_SYSTEM_UPGRADE" = "true" ]; then
    echo "--- (REMOTE) Performing full system upgrade... ---"
    apt-get upgrade -y
fi

echo "--- (REMOTE) Installing prerequisites... ---"
apt-get install -y curl gpg

echo "--- (REMOTE) Adding Syncthing repository... ---"
curl -s -o /usr/share/keyrings/syncthing-archive-keyring.gpg https://syncthing.net/release-key.gpg
echo "deb [signed-by=/usr/share/keyrings/syncthing-archive-keyring.gpg] https://apt.syncthing.net/ syncthing stable" | tee /etc/apt/sources.list.d/syncthing.list

echo "--- (REMOTE) Updating repositories and installing Syncthing + gocryptfs... ---"
apt-get update
apt-get install -y ${syncthing_pkg} ${gocryptfs_pkg}

echo "--- (REMOTE) Checking for NAS user: ${NAS_USER}... ---"
if id -u "${NAS_USER}" >/dev/null 2>&1; then
    echo "User '${NAS_USER}' already exists. Skipping creation."
else
    echo "Creating user '${NAS_USER}'..."
    useradd -m -s /bin/bash "${NAS_USER}"
    echo "${NAS_USER}:${NAS_USER_PASSWORD}" | chpasswd
    echo "User ${NAS_USER} created."
fi

echo "--- (REMOTE) Configuring SFTP access for ${NAS_USER}... ---"
if grep -q "^Match User ${NAS_USER}$" /etc/ssh/sshd_config; then
    echo "SFTP configuration for ${NAS_USER} already exists in /etc/ssh/sshd_config. Skipping."
else
    echo "Adding SFTP configuration for ${NAS_USER} to /etc/ssh/sshd_config."
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    bash -c 'cat >> /etc/ssh/sshd_config' <<EOT

# SFTP chroot jail for the NAS user
Match User ${NAS_USER}
    ChrootDirectory %h
    ForceCommand internal-sftp
    AllowTcpForwarding no
    X11Forwarding no
EOT
fi

echo "--- (REMOTE) Restarting SSH service... ---"
systemctl restart sshd

echo "--- (REMOTE) Creating NAS data directories... ---"
su -s /bin/bash -c "mkdir -p '${FINAL_ENCRYPTED_DATA_DIR}'" "${NAS_USER}"
su -s /bin/bash -c "mkdir -p '${FINAL_DECRYPTED_MOUNT_POINT}'" "${NAS_USER}"
echo "Directories created:"
echo "Encrypted storage: ${FINAL_ENCRYPTED_DATA_DIR}"
echo "Decrypted mount point: ${FINAL_DECRYPTED_MOUNT_POINT}"

echo "--- (REMOTE) Initializing gocryptfs encrypted directory... ---"
if [ -f "${FINAL_ENCRYPTED_DATA_DIR}/gocryptfs.conf" ]; then
    echo "gocryptfs directory already initialized. Skipping."
else
    echo "Initializing directory..."
    echo "${GOCRYPTFS_PASSWORD}" | su -s /bin/bash -c "gocryptfs -init -nonempty '${FINAL_ENCRYPTED_DATA_DIR}'" "${NAS_USER}"
fi

echo
echo "--- (REMOTE) DEPLOYMENT COMPLETE ---"
echo "The initial setup on the NAS is finished."
echo "The start.sh script has been copied to /start.sh on the NAS."
echo "After you reboot the NAS, you must log in and run '/start.sh' to decrypt the data drive and start Syncthing."
EOF
}