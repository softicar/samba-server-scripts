#!/bin/bash

####################################################################################
#
# add-share.sh  -  a SoftiCAR EAS file store administration script
#
# Configures a Samba file store server for a new SoftiCAR EAS instance:
# - Creates a new, login-less system user with a randomized password.
# - Creates a new SMB share.
# - Updates the Samba server configuration accordingly.
#
# Usage: ./add-share.sh
#
# Generated SMB passwords are saved to:
# ~/passwords/smb/<username>.txt
#
# For a given instance name of "my-something", the following things
# will be generated:
# - SMB and system user name:
#     "instance-my-something"
# - SMB share directory:
#     /mnt/data/shares/instance-my-something
# - SMB share configuration file:
#     /etc/samba/smb.conf.d/instance-my-something.conf
#
# Implementation note:
# Samba does not support a "smb.conf.d" directory out of the box. We therefore
# regenerate "includes.conf" everytime this script is used. After regeneration,
# this file will contain "include =" directives for each ".conf" file in
# "smb.conf.d". An include directive for "includes.conf", in turn, will be
# automatically appended to "/etc/samba/smb.conf" if missing.
#
# Author: Alexander Schmidt (alexander.schmidt@forspace-solutions.com)
#
####################################################################################

INSTANCE_NAME_CHARACTERS="a-z0-9-"
INSTANCE_NAME_EXAMPLE="some-instance-name"
INSTANCE_NAME_PROHIBITED_PREFIX="instance"
INSTANCE_NAME_REGEX="^[a-z]+([a-z0-9-]*[a-z0-9]+)?$"
SMB_PASSWORDS_DIR="$HOME/passwords/smb/"
SMB_SHARES_DIR="/mnt/data/shares/"
SMB_SHARES_DIR_USER="$USER"
SMB_SHARES_DIR_GROUP=$(groups | egrep -q '^users$' && echo "users" || echo "$USER")
SMB_CONF_FILE="/etc/samba/smb.conf"
SMB_CONF_DIR="/etc/samba/smb.conf.d/"
SMB_CONF_INCLUDES_FILE="/etc/samba/includes.conf"
SMB_CONF_INCLUDES_LINE="include = $SMB_CONF_INCLUDES_FILE"


# -------------------------------- Prerequisites -------------------------------- #

echo "This will create a system user and an SMB share for a new SoftiCAR EAS instance."

# Assert non-root user
[[ `id -u` = 0 ]] \
	&& { echo "FATAL: This script must NOT be run as root."; exit 1; }

# Check if samba is installed
[[ $(which smbd) ]] \
	|| { echo "FATAL: Samba is not installed."; exit 1; }

# Check if smb.conf exists
[[ -f $SMB_CONF_FILE ]] \
	|| { echo "FATAL: smb.conf not found at: $SMB_CONF_FILE"; exit 1; }

# Create SMB passwords dir if necessary
[[ ! -d $SMB_PASSWORDS_DIR ]] \
	&& { mkdir -p $SMB_PASSWORDS_DIR && chmod 700 $SMB_PASSWORDS_DIR && echo "Created SMB passwords directory at: $SMB_PASSWORDS_DIR" || exit 1; }

# Create SMB shares dir if necessary
[[ ! -d $SMB_SHARES_DIR ]] \
	&& { sudo mkdir -p $SMB_SHARES_DIR && sudo chown -R $SMB_SHARES_DIR_USER:$SMB_SHARES_DIR_GROUP $SMB_SHARES_DIR && echo "Created SMB shares directory at: $SMB_SHARES_DIR" || exit 1; }

# Create SMB configuration dir if necessary
[[ ! -d $SMB_CONF_DIR ]] \
	&& { sudo mkdir -p $SMB_CONF_DIR && echo "Created SMB configuration directory at: $SMB_CONF_DIR" || exit 1; }

# Create SMB configuration includes file if necessary
[[ ! -f $SMB_CONF_INCLUDES_FILE ]] \
	&& { sudo touch $SMB_CONF_INCLUDES_FILE || exit 1; }

# Create reference to SMB configuration includes file in smb.conf
grep -q "$SMB_CONF_INCLUDES_LINE" "$SMB_CONF_FILE" \
	|| echo "$SMB_CONF_INCLUDES_LINE" | sudo tee -a $SMB_CONF_FILE > /dev/null || { echo "FATAL: Failed to modify: $SMB_CONF_FILE"; exit 1; }


# -------------------------------- Main Script -------------------------------- #

# Prompt for an instance name
while true; do
	read -erp "Enter the name of the new instance [$INSTANCE_NAME_CHARACTERS]: " INSTANCE_NAME_INPUT
	if [[ -z $INSTANCE_NAME_INPUT ]]; then echo "Please enter an instance name."
	elif ! [[ $INSTANCE_NAME_INPUT =~ $INSTANCE_NAME_REGEX ]]; then echo "Please enter an instance name in the following format: $INSTANCE_NAME_EXAMPLE"
	elif [[ $INSTANCE_NAME_INPUT == $INSTANCE_NAME_PROHIBITED_PREFIX* ]]; then echo "The instance name must NOT start with: $INSTANCE_NAME_PROHIBITED_PREFIX"
	else break
	fi
done
INSTANCE_NAME="instance-"$INSTANCE_NAME_INPUT
echo "New instance name: [$INSTANCE_NAME]"


# ---------------- Sanity Checks ---------------- #

# Check if password file already exists
SMB_PASSWORD_FILE_PATH="$SMB_PASSWORDS_DIR""$INSTANCE_NAME"".txt"
[[ -f $SMB_PASSWORD_FILE_PATH ]] \
	&& { echo "FATAL: SMB password file already exists at: $SMB_PASSWORD_FILE_PATH"; exit 1; }

# Check if system user already exists
id $INSTANCE_NAME > /dev/null 2>&1 \
	&& { echo "FATAL: System user already exists: $INSTANCE_NAME"; exit 1; }

# Check if SMB share dir already exists
INSTANCE_SHARE_DIR="$SMB_SHARES_DIR""$INSTANCE_NAME"
[[ -d $INSTANCE_SHARE_DIR ]] \
	&& { echo "FATAL: SMB share directory already exists at: $INSTANCE_SHARE_DIR"; exit 1; }

# Check if instance specific SMB share definition file already exists
INSTANCE_SMB_SHARE_DEFINITION_FILE="$SMB_CONF_DIR""$INSTANCE_NAME"".conf"
[[ -f $INSTANCE_SMB_SHARE_DEFINITION_FILE ]] \
	&& { echo "FATAL: SMB share definition file already exists at: $INSTANCE_SMB_SHARE_DEFINITION_FILE"; exit 1; }


# ---------------- Execution ---------------- #

# Generate SMB password, and write it to a file
SMB_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 24)
echo $SMB_PASSWORD > $SMB_PASSWORD_FILE_PATH \
	&& echo "SMB password generated, and saved to: $SMB_PASSWORD_FILE_PATH" \
	|| { echo "FATAL: Failed to create SMB password file at: $SMB_PASSWORD_FILE_PATH"; exit 1; }

# Create system user
sudo adduser --no-create-home --disabled-password --disabled-login --gecos "" $INSTANCE_NAME \
	&& echo "System user created: $INSTANCE_NAME" \
	|| { echo "FATAL: Failed to create system user: $INSTANCE_NAME"; exit 1; }

# Create SMB share dir
sudo mkdir -p $INSTANCE_SHARE_DIR && sudo chown -R $INSTANCE_NAME:$INSTANCE_NAME $INSTANCE_SHARE_DIR \
	&& echo "Created SMB instance share directory at: $INSTANCE_SHARE_DIR" \
	|| { echo "FATAL: Failed to create SMB instance share directory at: $INSTANCE_SHARE_DIR"; exit 1; }

# Create SMB user with generated password
(echo "$SMB_PASSWORD"; echo "$SMB_PASSWORD") | sudo smbpasswd -s -a $INSTANCE_NAME \
	&& echo "SMB user created: $INSTANCE_NAME" \
	|| { echo "FATAL: Failed to create SMB user: $INSTANCE_NAME"; exit 1; }

# Create instance specific SMB share definition file
INSTANCE_SMB_SHARE_DEFINITION="[$INSTANCE_NAME]
path = $INSTANCE_SHARE_DIR
read only = no
valid users = $INSTANCE_NAME"
echo "$INSTANCE_SMB_SHARE_DEFINITION" | sudo tee $INSTANCE_SMB_SHARE_DEFINITION_FILE > /dev/null \
	|| { echo "FATAL: Failed to create instance specific SMB share definition file: $INSTANCE_SMB_SHARE_DEFINITION_FILE"; exit 1; }

# Regenerate SMB configuration includes file
GENERATED_FILE_WARNING="# THIS FILE IS GENERATED!
# DO NOT MODIFY IT MANUALLY!
# MANUAL CHANGES WILL BE OVERWRITTEN!
"
find $SMB_CONF_DIR -type f -name "*.conf" | awk '{print "include = " $0}' | (echo "$GENERATED_FILE_WARNING" && cat) | sudo tee $SMB_CONF_INCLUDES_FILE > /dev/null \
	&& echo "Regenerate SMB configuration includes file: $SMB_CONF_INCLUDES_FILE" \
	|| { echo "FATAL: Failed to regenerate SMB configuration includes file: $SMB_CONF_INCLUDES_FILE"; exit 1; }

# Ask to restart Samba service
read -p "Samba configuration has changed. Restart Samba service now? [Y/n]: " -r; REPLY=${REPLY:-"Y"};
[[ $REPLY =~ ^[Yy]$ ]] && sudo service smbd restart

echo "Successfully set up SMB share for instance: $INSTANCE_NAME"
echo "kthxbye"
