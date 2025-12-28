# NAS Deployment Scripts

## Overview

This set of scripts automates the initial setup and configuration of a Network Attached Storage (NAS) device. It is designed to prepare a fresh Debian-based system with essential services for secure file storage and synchronization.

> **⚠️ Important Security Notice**
>
> This script is designed for personal use in a trusted local network (LAN) environment, such as a home setup protected by a firewall. It is not hardened for enterprise or production use and lacks the resilience and advanced security features required for such environments. Use with caution.

The main features include:
- Creating a dedicated user for the NAS.
- Setting up an encrypted file system using `gocryptfs`.
- Installing and enabling `Syncthing` to run as a service for the new user.
- Configuring a secure SFTP chroot jail for the user to restrict access to their home directory.

## Prerequisites

- **Local Machine:** A Unix-like environment with `bash` and an `ssh` client.
- **Remote NAS:** A server running a Debian-based Linux distribution (tested with Debian and Raspberry Pi OS) with SSH access.

## Configuration

All configuration is managed through the `config.sh` file. Before running the deployment, you should review and edit this file to match your requirements.

| Variable                  | Description                                                                                             |
| ------------------------- | ------------------------------------------------------------------------------------------------------- |
| `SSH_TARGET`              | The SSH connection details for the target NAS (e.g., `user@hostname`).                                  |
| `NAS_USER`                | The username to be created on the NAS.                                                                  |
| `NAS_USER_PASSWORD`       | The password for the new user. **It is not recommended to store this in the file.**                     |
| `GOCRYPTFS_PASSWORD`      | The password for the encrypted volume. **It is not recommended to store this in the file.**             |
| `ENCRYPTED_DATA_DIR`      | The full path for the gocryptfs encrypted data directory. Defaults to `/home/<NAS_USER>/nas_encrypted`. |
| `DECRYPTED_MOUNT_POINT`   | The full path for the gocryptfs decrypted mount point. Defaults to `/home/<NAS_USER>/NAS`.              |
| `PERFORM_SYSTEM_UPGRADE`  | Set to `true` to run `apt-get upgrade`. Defaults to `false`.                                            |
| `SYNCTHING_VERSION`       | A specific version of Syncthing to install (e.g., `1.23.7`). If empty, the latest is installed.         |
| `GOCRYPTFS_VERSION`       | A specific version of gocryptfs to install. If empty, the latest is installed.                          |

If you leave the password fields empty in `config.sh`, the script will prompt you to enter them securely.

## Usage

1.  **Configure:** Edit the `config.sh` file with your desired settings.
2.  **Execute:** Run the main deployment script:
    ```bash
    ./deploy.sh
    ```

The script will connect to the remote NAS via SSH and perform the setup steps.

## Post-Deployment

After the script has finished successfully, a new script named `/start.sh` will be created on the remote NAS. To complete the setup and start the services, you must:

1.  **Reboot the NAS.**
2.  **Log in** to the NAS via SSH.
3.  **Run the start script:**
    ```bash
    sudo /start.sh
    ```

This script will prompt for the gocryptfs password to decrypt and mount the storage volume, and then it will start the Syncthing service.

## Limitations

### Root SSH Access
The deployment script requires root access to the target machine to perform system-level configurations, such as installing packages and modifying `sshd_config`. For the script to work, you must enable root login via SSH. It is recommended to do this temporarily and disable it after the setup is complete.

1.  **Log in** to your future NAS as a user with `sudo` privileges.
2.  **Edit the SSH daemon configuration:**
    ```bash
    sudo nano /etc/ssh/sshd_config
    ```
3.  **Modify the `PermitRootLogin` setting:**
    Find the line `#PermitRootLogin prohibit-password` (or similar) and change it to:
    ```
    PermitRootLogin yes
    ```
4.  **Restart the SSH service:**
    ```bash
    sudo systemctl restart ssh
    ```

Once the deployment is finished, it is highly recommended to revert this change for security reasons:
```
PermitRootLogin prohibit-password
```
and restart the SSH service again.

### Script Behavior
This script is designed for initial setup but has been made idempotent for several key operations to allow for safer re-runs.

**Idempotent Operations**
- **User Creation:** Checks if the user exists before creating one.
- **SFTP Configuration:** Checks if the configuration block exists in `sshd_config` before adding it.
- **gocryptfs Initialization:** Checks if the directory is already initialized before running `gocryptfs -init`.

**Non-Deterministic Operations**
- **Package Installation:** `apt-get update` fetches the latest package lists. While you can pin versions for `syncthing` and `gocryptfs` in the `config.sh` file, other dependencies and the system upgrade (`PERFORM_SYSTEM_UPGRADE=true`) are non-deterministic and will install the latest available versions at the time of execution.

### Security
- Storing plaintext passwords in `config.sh` is a security risk. The recommended approach is to leave the password variables empty and enter them when prompted by the script.
