#!/bin/bash

########################################################################################
#
# softicar-samba-server-setup.sh
#
# Sets up a Samba based file store server for a SoftiCAR EAS instance:
# - Installs Samba.
# - Creates a new, login-less system user with a randomized password.
# - Adds that user to the Samba configuration.
# - Creates a share directory, and configures a share.
#
# Usage: ./softicar-samba-server-setup.sh
#
# Author: Alexander Schmidt (alexander.schmidt@forspace-solutions.com)
#
########################################################################################

SAMBA_CONFIG_FILE=/etc/samba/smb.conf
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
	read -rp "Samba share directory $SAMBA_SHARE_DIR already exists. Continue anyway? [y/N]: "
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
	read -rp "Samba user $SAMBA_USER is already configured. Continue anyway? [y/N]: "
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

SMB_CONF_CONTENT="
path = $SAMBA_SHARE_DIR
read only = no
valid users = $SAMBA_USER
"
echo "Creating Samba configuration file..."
echo $SMB_CONF_CONTENT | sudo tee $SAMBA_CONFIG_FILE > /dev/null \
	&& { echo "Samba configuration file created."; } \
	|| { echo "FATAL: Failed to create $SAMBA_CONFIG_FILE"; exit 1; }


# ---- Profit ---- #

echo "All done."
echo ""

echo "vvvv  STORE THIS INFORMATION IN A SAFE PLACE  vvvv"
echo "Samba credentials:"
echo "User: "$SAMBA_USER
echo "Password: "$([[ -v SAMBA_PASSWORD ]] && echo $SAMBA_PASSWORD || echo "(unchanged)" )
echo "^^^^  STORE THIS INFORMATION IN A SAFE PLACE  ^^^^"
echo ""

echo "Bye."
