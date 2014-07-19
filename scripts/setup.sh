#!/bin/bash --login

clear
unset HISTFILE

echo ">>>>>>>>>> Start time: $(date) <<<<<<<<<<<<"

export EXECUTION_DIR=$PWD
export LOG_FILE=$EXECUTION_DIR/setup.log
rm -rf $LOG_FILE

echo ">>>>>>>>>> Start time: $(date) <<<<<<<<<<<<" >> $LOG_FILE

export BOSH_DIRECTOR_URL=192.168.50.4:25555
export BOSH_USER=admin
export BOSH_PASSWORD=admin

export BOSH_LITE_REPO=https://github.com/cloudfoundry/bosh-lite.git
export CF_RELEASE_REPO=https://github.com/cloudfoundry/cf-release.git
export CF_ACCEPTANCE_TESTS_REPO=https://github.com/cloudfoundry/cf-acceptance-tests.git

export AWS_STEM_CELL_URL=http://bosh-jenkins-gems-warden.s3.amazonaws.com/stemcells
export STEM_CELL_TO_INSTALL=latest-bosh-stemcell-warden.tgz
export STEM_CELL_URL=$AWS_STEM_CELL_URL/$STEM_CELL_TO_INSTALL

export VAGRANT_VERSION=1.6.2

export RVM_DOWNLOAD_URL=https://get.rvm.io
export HOMEBREW_DOWNLOAD_URL=https://raw.github.com/Homebrew/homebrew/go/install

export LINUXBREW_GIT_REPO=https://github.com/Homebrew/linuxbrew.git
export PROVIDER=$1

. logMessages.sh

echo "######  Install Open Source CloudFoundry ######"
if [ $# -lt 2 ]; then
	echo "Usage: ./setup.sh <provider> <install-dir>"
	printf "\t %s \t\t %s \n\t\t\t\t %s \n" "provider:" "Enter 1 for Virtual Box" "Enter 2 for VMWare Fusion"
	printf "\t %s \t\t %s \n" "install-dir:" "Specify the install directory"
	printf "\t %s \t\t\t %s \n" "-f" "Force remove old installation and install fresh"
	exit 1
fi

if [ ! -d $2 ]; then
	logError "Non-existant directory: $2"
fi

export BOSH_RELEASES_DIR=$2

set -e
./validation.sh $PROVIDER

read -s -p "Enter Password: " PASSWORD
if [ -z $PASSWORD ]; then
	logError "Please provide the sudo password"
fi

echo

cmd=`$EXECUTION_DIR/login.sh $USER $PASSWORD`
if [[ $cmd == *Sorry* ]]; then
	logError "Invalid password"
else
	logSuccess "Password Validated"
fi

OS=`uname`

VAGRANT_INSTALLED=`which vagrant`
if [ -z $VAGRANT_INSTALLED ]; then
	logError "You don't have vagrant Installed. I knew you would never read instructions. Install that first and then come back."
fi

$EXECUTION_DIR/brew_install.sh

echo "###### Clone Required Git Repositories ######"
if [ ! -d "$BOSH_RELEASES_DIR/bosh-lite" ]; then
	git clone $BOSH_LITE_REPO $BOSH_RELEASES_DIR/bosh-lite >> $LOG_FILE 2>&1
elif [ $3 == "-f" ]; then
	$EXECUTION_DIR/perform_cleanup.sh
fi

if [ ! -d "$BOSH_RELEASES_DIR/cf-release" ]; then
	git clone $CF_RELEASE_REPO $BOSH_RELEASES_DIR/cf-release >> $LOG_FILE 2>&1
fi

export CF_LATEST_RELEASE_VERSION=`tail -1 $BOSH_RELEASES_DIR/cf-release/releases/index.yml | cut -d':' -f2 | cut -d' ' -f2`

if [[ -n ${CF_LATEST_RELEASE_VERSION//[0-9]/} ]]; then
	export CF_LATEST_RELEASE_VERSION=`echo $CF_LATEST_RELEASE_VERSION | tr -d "'"`
fi

logInfo "Latest version of Cloud Foundry is: $CF_LATEST_RELEASE_VERSION"
export CF_RELEASE=cf-$CF_LATEST_RELEASE_VERSION.yml
logInfo "Deploy CF release $CF_RELEASE"

echo "###### Validate the entered cf version ######"
if [ ! -f $BOSH_RELEASES_DIR/cf-release/releases/$CF_RELEASE ]; then
	logError "Invalid CF version selected. Please correct and try again"
fi

export EXPECTED_RUBY_VERSION_BOSH="1.9.3-p484"
export EXPECTED_RUBY_VERSION_CF_RELEASE="1.9.3-p484"

set +e
$EXECUTION_DIR/ruby_install.sh

INSTALLED_WGET=`which wget`
if [ -z "$INSTALLED_WGET" ]; then
	echo "###### Installing wget ######"
	brew install wget >> $LOG_FILE 2>&1
fi

INSTALLED_SPIFF=`which spiff`
if [ -z "$INSTALLED_SPIFF" ]; then
	echo "###### Install spiff ######"
	brew tap xoebus/homebrew-cloudfoundry &> $LOG_FILE 2>&1
	brew install spiff &> $LOG_FILE 2>&1
fi

echo "###### Switching to bosh-lite ######"
cd $BOSH_RELEASES_DIR/bosh-lite  &> $LOG_FILE 2>&1

set -e
echo "###### Pull latest changes (if any) for bosh-lite ######"
git pull >> $LOG_FILE 2>&1

echo "###### Download warden ######"
if [ ! -f $STEM_CELL_TO_INSTALL ]; then
    echo "###### Downloading... warden ######"
    wget --progress=bar:force $STEM_CELL_URL -o $LOG_FILE 2>&1
else
	logInfo "Skipping warden download, local copy exists"
fi

echo "###### Bundle bosh-lite ######"
bundle &> $LOG_FILE 2>&1

set +e
echo "###### Switching to cf-release ######"
cd $BOSH_RELEASES_DIR/cf-release

set -e

echo "###### Update cf-release to sync the sub-modules ######"
./update &> $LOG_FILE

echo "###### Bundle cf-release ######"
bundle &> $LOG_FILE 2>&1

set +e
echo "###### Switching to bosh-lite ######"
cd $BOSH_RELEASES_DIR/bosh-lite

set -e
PLUGIN_INSTALLED=false
VMWARE_PLUGIN_INSTALLED=`vagrant plugin list`
STRING_TO_LOOK_FOR="vagrant-vmware-fusion"
if echo "$VMWARE_PLUGIN_INSTALLED" | grep -q "$STRING_TO_LOOK_FOR"; then
	PLUGIN_INSTALLED=true
fi

set -e

echo "###### Vagrant up ######"
if [ $PROVIDER -eq 1 ]; then
	if [ $PLUGIN_INSTALLED == true ]; then
		logInfo "Found VMWare Fusion plugin, uninstalling it"
		vagrant plugin uninstall vagrant-vmware-fusion
	fi

	vagrant up >> $LOG_FILE 2>&1
else
	if [ $PLUGIN_INSTALLED == true ]; then
		logInfo "Vagrant Plugin already installed"
	else
		vagrant plugin install vagrant-vmware-fusion >> $LOG_FILE 2>&1
		vagrant plugin license vagrant-vmware-fusion $EXECUTION_DIR/license.lic >> $LOG_FILE 2>&1
	fi

	vagrant up --provider vmware_fusion >> $LOG_FILE 2>&1
fi

BOSH_INSTALLED=`which bosh`
if [ -z "$BOSH_INSTALLED" ]; then
	logError "Bosh command not found, please fire rvm gemset use bosh-lite"
fi

echo "###### Target BOSH to BOSH director ######"
bosh target $BOSH_DIRECTOR_URL

echo "###### Setup bosh target and login ######"
bosh login $BOSH_USER $BOSH_PASSWORD

echo "###### Set the routing tables ######"
echo $PASSWORD | sudo -S scripts/add-route >> $LOG_FILE 2>&1

set +e
echo "###### Upload stemcell ######"
bosh upload stemcell --skip-if-exists $BOSH_RELEASES_DIR/bosh-lite/$STEM_CELL_TO_INSTALL >> $LOG_FILE 2>&1

STEM_CELL_NAME=$( bosh stemcells | grep -o "bosh-warden-[^[:space:]]*" )
echo "###### Uploaded stemcell $STEM_CELL_NAME ######"

echo "###### Switching to cf-release ######"
cd $BOSH_RELEASES_DIR/cf-release

logCustom 9 "###### Upload cf-release $CF_RELEASE ######"
bosh upload release releases/$CF_RELEASE &> $LOG_FILE 2>&1

echo "###### Switching to bosh-lite ######"
cd $BOSH_RELEASES_DIR/bosh-lite

set -e
echo "###### Generate a manifest at manifests/cf-manifest.yml ######"
./scripts/make_manifest_spiff &> $LOG_FILE 2>&1

echo "###### Deploy the manifest manifests/cf-manifest.yml ######"
bosh deployment manifests/cf-manifest.yml &> $LOG_FILE 2>&1

#sed -i.bak 's/bosh-warden-boshlite-ubuntu/'"$STEM_CELL_NAME"'/' $PWD/manifests/cf-manifest.yml

set +e
logCustom 9 "###### Deploy CF to BOSH-LITE (THIS WOULD TAKE SOME TIME) ######"
echo "yes" | bosh deploy &> $LOG_FILE 2>&1

echo "###### Executing BOSH VMS to ensure all VMS are running ######"
BOSH_VMS_INSTALLED_SUCCESSFULLY=$( bosh vms | grep -o "failing" )
if [ ! -z "$BOSH_VMS_INSTALLED_SUCCESSFULLY" ]; then
	logError "Not all BOSH VMs are up. Please check logs for more info"
fi

$EXECUTION_DIR/setup_cf_commandline.sh

echo ">>>>>>>>>> End time: $(date) <<<<<<<<<<<<"
echo ">>>>>>>>>> End time: $(date) <<<<<<<<<<<<" >> $LOG_FILE

logSuccess "###### Congratulations: Open Source CloudFoundry setup complete! ######"
