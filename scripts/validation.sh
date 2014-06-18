#!/bin/bash
. logMessages.sh

if [ $1 -eq 1 ] || [ $1 -eq 2 ]; then
	if [ $1 -eq 1 ]; then 
		logInfo "Provider selected : Virtual Box" 
		VIRTUAL_BOX_INSTALLED=`which virtualbox`
		if [ -z $VIRTUAL_BOX_INSTALLED ]; then
			logError "VirtualBox not installed. Please download and install it from https://www.virtualbox.org/" 
		fi
	else 
		logInfo "Provider selected : VMWare Fusion."
		if [ ! -f $BOSH_RELEASES_DIR/license.lic ]; then
			ERROR_MSG="Please place the license.lic file in $BOSH_RELEASES_DIR" 
			INFO_MSG="Ensure you have the license.lic available. https://www.vagrantup.com/vmware"			
			logError "$ERROR_MSG" "$INFO_MSG"
		fi
	fi
else
	logError "Please provide the valid selection for the provider"
fi

if [ ! -f "$BOSH_RELEASES_DIR/login.sh" ] || [ ! -f "$BOSH_RELEASES_DIR/brew_install.sh" ] || [ ! -f "$BOSH_RELEASES_DIR/logMessages.sh" ] || [ ! -f "$BOSH_RELEASES_DIR/ruby_install.sh" ]; then
	ERROR_MSG="Dude you never read instructions"
	INFO_MSG="Place the all the *.sh files under $BOSH_RELEASES_DIR/"
	logError "$ERROR_MSG" "$INFO_MSG"
fi