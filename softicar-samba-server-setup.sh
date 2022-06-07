#!/bin/bash

########################################################################################
#
# softicar-samba-server-setup.sh  -  a Samba file server setup script for SoftiCAR EAS
#
# Sets up a Samba file store server for a new SoftiCAR EAS instance:
# - Creates a new, login-less system user with a randomized password.
# - Configures an SMB share.
#
# Usage: ./softicar-samba-server-setup.sh
#
# Author: Alexander Schmidt (alexander.schmidt@forspace-solutions.com)
#
########################################################################################

SAMBA_CONFIG_FILE=/etc/smb/smb.conf
SAMBA_SHARE_DIR=/var/lib/softicar-files
SAMBA_USER=softicar-files


# Greetings
echo "This will install and configure the Samba based file store for a new SoftiCAR EAS instance."
read -p "Continue? [Y/n]: " -r; REPLY=${REPLY:-"Y"};
[[ ! $REPLY =~ ^[Yy]$ ]] \
	&& { echo "Bye."; exit 1; }


# Assert non-root user
[[ `id -u` = 0 ]] \
	&& { echo "FATAL: This script must NOT be run as root."; exit 1; }


# Install Samba if necessary
if [[ $(which smbd) ]]; then
	read -p "Samba is already installed. Continue anyway? [y/N]: " -r
	[[ ! $REPLY =~ ^[Yy]$ ]] \
		&& { echo "Bye."; exit 1; }
else
	sudo apt-get update && sudo apt-get install -y samba \
		|| { echo "FATAL: Failed to install Samba."; exit 1; }
fi


# Create Samba user if necessary
read -erp "Enter the name of the Samba user [$SAMBA_USER]: "; REPLY=${REPLY:-"$SAMBA_USER"};
SAMBA_USER=$REPLY

echo "entered: $SAMBA_USER"

if id "$SAMBA_USER" > /dev/null 2>&1; then
	read -p "System user $SAMBA_USER already exists. Continue anyway? [y/N]: " -r
	[[ ! $REPLY =~ ^[Yy]$ ]] \
		&& { echo "Bye."; exit 1; }
else
	# Create Samba user
	sudo adduser --no-create-home --disabled-password --disabled-login --gecos "" $SAMBA_USER \
		|| { echo "FATAL: Failed to create Samba user: $SAMBA_USER"; exit 1; }
fi


# Create Samba share dir
read -erp "Enter the Samba share directory [$SAMBA_SHARE_DIR]: "; REPLY=${REPLY:-"$SAMBA_SHARE_DIR"};
SAMBA_SHARE_DIR=$REPLY
if [[ -d "$SAMBA_SHARE_DIR" ]]; then
	read -p "Samba share directory $SAMBA_SHARE_DIR already exists. Continue anyway? [y/N]: " -r
	[[ ! $REPLY =~ ^[Yy]$ ]] \
		&& { echo "Bye."; exit 1; }
else
	sudo mkdir "$SAMBA_SHARE_DIR" \
		|| { echo "FATAL: Failed to create Samba share directory: $SAMBA_SHARE_DIR"; exit 1; }
fi


# Change permissions of Samba share dir
sudo chown -R $SAMBA_USER:$SAMBA_USER $SAMBA_SHARE_DIR \
	|| { echo "FATAL: Failed to change permissions of Samba share directory: $SAMBA_SHARE_DIR"; exit 1; }


# Configure Samba user with generated password
if sudo pdbedit -L -u $SAMBA_USER > /dev/null 2>&1; then
	read -p "Samba user $SAMBA_USER is already configured. Continue anyway? [y/N]: " -r
	[[ ! $REPLY =~ ^[Yy]$ ]] \
		&& { echo "Bye."; exit 1; }
else
	# Generate Samba password
	SAMBA_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 24) \
		|| { echo "FATAL: Failed to generate Samba password."; exit 1; }

	# Configure Samba user
	(echo "$SAMBA_PASSWORD"; echo "$SAMBA_PASSWORD") | sudo smbpasswd -s -a $SAMBA_USER \
		|| { echo "FATAL: Failed to configure Samba user: $SAMBA_USER"; exit 1; }
fi


# Rename existing Samba configuration file
[[ -f $SAMBA_CONFIG_FILE ]] \
	&& { sudo mv $SAMBA_CONFIG_FILE $SAMBA_CONFIG_FILE".old_$(date +%F_%H-%M-%S)" || echo "FATAL: Failed to rename $SAMBA_CONFIG_FILE."; exit 1; }


# Create new Samba configuration file
SMB_CONF_CONTENT="
path = $SAMBA_SHARE_DIR
read only = no
valid users = $SAMBA_USER
"
echo $SMB_CONF_CONTENT | sudo tee $SAMBA_CONFIG_FILE > /dev/null \
	|| { echo "FATAL: Failed to create $SAMBA_CONFIG_FILE"; exit 1; }


# Profit
echo "All done."
echo ""

echo "vvvv  STORE THIS INFORMATION IN A SAFE PLACE  vvvv"
echo "Samba credentials:"
echo "User: "$SAMBA_USER
echo "Password: "$([[ -v SAMBA_PASSWORD ]] && echo $SAMBA_PASSWORD || echo "(unchanged)" )
echo "^^^^  STORE THIS INFORMATION IN A SAFE PLACE  ^^^^"
echo ""

echo "Bye."
