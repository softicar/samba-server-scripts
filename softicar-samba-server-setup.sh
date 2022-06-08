#!/bin/bash

########################################################################################
#
# softicar-samba-server-setup.sh
#
# Sets up a Samba server as a file store for a SoftiCAR EAS instance:
# - Installs Samba.
# - Creates a new, login-less system user with a randomized password.
# - Adds that user to the Samba configuration.
# - Creates a share directory, and configures the share.
#
# After running this script, the Samba based file store will be ready to use.
#
# Usage: ./softicar-samba-server-setup.sh
#
# Author: Alexander Schmidt (alexander.schmidt@forspace-solutions.com)
#
########################################################################################

SAMBA_CONFIG_FILE=/etc/samba/smb.conf
SAMBA_SHARE=softicar-files
SAMBA_SHARE_DIR=/var/lib/softicar-files
SAMBA_USER=softicar-files


# ---- Functions ---- #

function assert_reply_yes_or_exit {
	[[ ! $REPLY =~ ^[Yy]$ ]] && { echo "Bye."; exit 1; }
}


# ---- Greetings ---- #

echo "This will install and configure the Samba based file store for a SoftiCAR EAS instance."
read -rp "Continue? [Y/n]: "; REPLY=${REPLY:-"Y"};
assert_reply_yes_or_exit


# ---- Assert non-root user ---- #

[[ `id -u` = 0 ]] \
	&& { echo "FATAL: This script must NOT be run as root."; exit 1; }


# ---- Install Samba if necessary ---- #

if [[ $(which smbd) ]]; then
	read -rp "Samba is already installed. Skip installation and continue? [y/N]: "
	assert_reply_yes_or_exit
else
	echo "Installing Samba..."
	sudo apt-get update && sudo apt-get install -y samba \
		&& { echo "Samba installed."; } \
		|| { echo "FATAL: Failed to install Samba."; exit 1; }
fi


# ---- Create Samba user if necessary ---- #

read -erp "Enter the name of the Samba user [$SAMBA_USER]: "; REPLY=${REPLY:-"$SAMBA_USER"};
SAMBA_USER=$REPLY

if id "$SAMBA_USER" > /dev/null 2>&1; then
	read -rp "System user $SAMBA_USER already exists. Skip user creation and continue? [y/N]: "
	assert_reply_yes_or_exit
else
	echo "Creating Samba user..."
	sudo adduser --no-create-home --disabled-password --disabled-login --gecos "" $SAMBA_USER \
		&& { echo "Samba user created."; } \
		|| { echo "FATAL: Failed to create Samba user: $SAMBA_USER"; exit 1; }
fi


# ---- Create Samba share dir ---- #

read -erp "Enter the Samba share directory [$SAMBA_SHARE_DIR]: "; REPLY=${REPLY:-"$SAMBA_SHARE_DIR"};
SAMBA_SHARE_DIR=$REPLY

if [[ -d "$SAMBA_SHARE_DIR" ]]; then
	read -rp "Samba share directory $SAMBA_SHARE_DIR already exists. Use that directory and continue? [y/N]: "
	assert_reply_yes_or_exit
else
	echo "Creating Samba share directory..."
	sudo mkdir "$SAMBA_SHARE_DIR" \
		&& { echo "Samba share directory created."; } \
		|| { echo "FATAL: Failed to create Samba share directory: $SAMBA_SHARE_DIR"; exit 1; }
fi


# ---- Change ownership of Samba share dir ---- #

echo "Changing ownership of Samba share directory..."
sudo chown -R $SAMBA_USER:$SAMBA_USER $SAMBA_SHARE_DIR \
	&& { echo "Changed ownership of Samba share directory."; } \
	|| { echo "FATAL: Failed to change ownership of Samba share directory: $SAMBA_SHARE_DIR"; exit 1; }


# ---- Configure Samba user with generated password ---- #

if sudo pdbedit -L -u $SAMBA_USER > /dev/null 2>&1; then
	read -rp "Samba user $SAMBA_USER is already configured. Use that user and continue? [y/N]: "
	assert_reply_yes_or_exit
else
	echo "Generating Samba password..."
	SAMBA_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 24) \
		&& { echo "Samba password generated."; } \
		|| { echo "FATAL: Failed to generate Samba password."; exit 1; }

	echo "Configuring Samba user..."
	(echo "$SAMBA_PASSWORD"; echo "$SAMBA_PASSWORD") | sudo smbpasswd -s -a $SAMBA_USER \
		&& { echo "Samba user configured."; } \
		|| { echo "FATAL: Failed to configure Samba user: $SAMBA_USER"; exit 1; }
fi


# ---- Rename existing Samba configuration file ---- #

if [[ -f $SAMBA_CONFIG_FILE ]]; then
	echo "Renaming existing Samba configuration file..."
	sudo mv $SAMBA_CONFIG_FILE $SAMBA_CONFIG_FILE".old_$(date +%F_%H-%M-%S)" \
		&& { echo "Existing Samba configuration file renamed."; } \
		|| { echo "FATAL: Failed to rename $SAMBA_CONFIG_FILE."; exit 1; }
fi


# ---- Create new Samba configuration file ---- #

echo "Creating Samba configuration file..."
cat << EOF | sudo tee $SAMBA_CONFIG_FILE > /dev/null && { echo "Samba configuration file created."; } || { echo "FATAL: Failed to create Samba configuration file: $SAMBA_CONFIG_FILE"; exit 1; }
[$SAMBA_SHARE]
path = $SAMBA_SHARE_DIR
read only = no
valid users = $SAMBA_USER
EOF


# ---- Enable Samba daemon ---- #

echo "Enabling Samba daemon..."
sudo systemctl enable smbd > /dev/null 2>&1 \
	&& { echo "Samba daemon enabled."; } \
	|| { echo "FATAL: Failed to enable Samba daemon."; exit 1; }


# ---- Restart Samba daemon ---- #

echo "Restarting Samba daemon..."
sudo systemctl restart smbd \
	&& { echo "Samba daemon restarted."; } \
	|| { echo "FATAL: Failed to restart Samba daemon."; exit 1; }


# ---- Profit ---- #

echo "Samba server was installed and set up successfully."

if [[ -v SAMBA_PASSWORD ]]; then
	echo ""
	echo "vvvv  STORE THIS INFORMATION IN A SAFE PLACE  vvvv"
	echo "Samba User:     "$SAMBA_USER
	echo "Samba Password: "$SAMBA_PASSWORD
	echo "^^^^  STORE THIS INFORMATION IN A SAFE PLACE  ^^^^"
	echo ""
fi

echo "Bye."
