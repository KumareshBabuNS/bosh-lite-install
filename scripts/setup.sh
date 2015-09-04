#!/bin/bash --login

echo ">>>>>>>>>> Start time: $(date) <<<<<<<<<<<<"

clear
unset HISTFILE

. common.sh
. cf_install.sh
. diego_install.sh
. logMessages.sh

echo "######  Install Open Source CloudFoundry ######"
if [ $# -lt 2 ]; then
	echo "Usage: ./setup.sh <provider> <install-dir> <options>"
	printf "\t %s \t\t %s \n\t\t\t\t %s \n" "provider:" "Enter 1 for Virtual Box" "Enter 2 for VMWare Fusion"
	printf "\t %s \t\t %s \n" "install-dir:" "Specify the install directory"
	printf "\t %s \t\t\t %s \n" "-f" "Force remove old installation and install fresh"
	printf "\t %s \t\t\t %s \n" "-v=" "version to install"
	exit 1
fi

if [ ! -d $2 ]; then
	logError "Non-existant directory: $2"
fi

export PROVIDER=$1
export BOSH_RELEASES_DIR=$2

if [[ $3 = "-f" || $4 = "-f" ]]; then
	export FORCE_DELETE="-f"
fi

if [[ $3 == *"-v"* ]]; then
	export RELEASE_VERSION_REQUIRED=`echo $3 | tr -d '\-v='`
	echo $RELEASE_VERSION_REQUIRED
elif [[ $4 == *"-v"* ]]; then
	export RELEASE_VERSION_REQUIRED=`echo $4 | tr -d '\-v='`
	echo $RELEASE_VERSION_REQUIRED
fi

export SELECTION=0

while [[ $SELECTION -ne 1 && $SELECTION -ne 2 ]]; do
	echo "Select the option:"
	printf " %s \t %s \n" "1:" "CF-RELEASE"
	printf " %s \t %s \n" "2:" "DIEGO-RELEASE"
	read -p "What's it you wish to install? " SELECTION
	echo
done

export OS=`uname`

export BOSH_LITE_DIR=$BOSH_RELEASES_DIR/bosh-lite
export CF_RELEASE_DIR=$BOSH_RELEASES_DIR/cf-release
export DIEGO_RELEASE_DIR=$BOSH_RELEASES_DIR/diego-release
export GARDEN_RELEASE_DIR=$BOSH_RELEASES_DIR/garden-linux-release

export RETAKE_SNAPSHOT=false

pre_install

if [[ $SELECTION = 1 ]]; then
	export CF_VERSION_REQUIRED=$RELEASE_VERSION_REQUIRED
	execute_cf_deployment
elif [[ $SELECTION = 2 ]]; then
	export DIEGO_VERSION_REQUIRED=$RELEASE_VERSION_REQUIRED
	execute_diego_deployment
fi

post_install_activities

echo ">>>>>>>>>> End time: $(date) <<<<<<<<<<<<"
echo ">>>>>>>>>> End time: $(date) <<<<<<<<<<<<" >> $LOG_FILE

logSuccess "###### Congratulations: Open Source CloudFoundry setup complete! ######"
