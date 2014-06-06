#!/bin/bash --login

clear
unset HISTFILE

echo ">>>>>>>>>> Start time: $(date) <<<<<<<<<<<<"

export BOSH_RELEASES_DIR=$PWD
export LOG_FILE=$BOSH_RELEASES_DIR/setup.log

rm -rf $LOG_FILE

echo ">>>>>>>>>> Start time: $(date) <<<<<<<<<<<<" >> $LOG_FILE

export BOSH_USER=admin
export BOSH_PASSWORD=admin
export CF_USER=admin
export CF_PASSWORD=admin

export BOSH_DIRECTOR_URL=192.168.50.4:25555
export CLOUD_CONTROLLER_URL=https://api.10.244.0.34.xip.io/
export ORG_NAME=local
export SPACE_NAME=development

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

. logMessages.sh

echo "######  Install Open Source CloudFoundry ######"
if [ $# -ne 2 ]; then
	echo "Usage: ./setup.sh <cf-release-version> <provider>"
	printf "\t %s \t %s \n" "cf-release-version:" "Cloud foundry version to deploy on vagrant"
	printf "\t %s \t\t %s \n\t\t\t\t %s \n" "provider:" "Enter 1 for Virtual Box" "Enter 2 for VMWare Fusion"
	exit 1
fi

set -e
./validation.sh $1 $2

read -s -p "Enter Password: " PASSWORD
if [ -z $PASSWORD ]; then
	logError "Please provide the sudo password"
fi

echo

cmd=`$BOSH_RELEASES_DIR/login.sh $USER $PASSWORD`
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

./brew_install.sh

export CF_RELEASE=cf-$1.yml
logInfo "Deploy CF release $CF_RELEASE"

echo "###### Clone Required Git Repositories ######"
if [ ! -d "bosh-lite" ]; then
	git clone $BOSH_LITE_REPO bosh-lite >> $LOG_FILE 2>&1
fi

if [ ! -d "cf-release" ]; then
	git clone $CF_RELEASE_REPO cf-release >> $LOG_FILE 2>&1
fi

if [ ! -d "cf-acceptance-tests" ]; then
	git clone $CF_ACCEPTANCE_TESTS_REPO cf-acceptance-tests >> $LOG_FILE 2>&1
fi

echo "###### Validate the entered cf version ######"
if [ ! -f $BOSH_RELEASES_DIR/cf-release/releases/$CF_RELEASE ]; then
	logError "Invalid CF version selected. Please correct and try again"
fi

export EXPECTED_RUBY_VERSION_BOSH=`cat $BOSH_RELEASES_DIR/bosh-lite/.ruby-version`
export EXPECTED_RUBY_VERSION_CF_RELEASE=`cat $BOSH_RELEASES_DIR/cf-release/.ruby-version`

set +e
./ruby_install.sh

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
if [ $2 -eq 1 ]; then
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
		vagrant plugin license vagrant-vmware-fusion $BOSH_RELEASES_DIR/license.lic >> $LOG_FILE 2>&1
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

set -e
echo "###### Setup cloudfoundry cli ######"
GO_CF_VERSION=`which gcf`
if [ -z "$GO_CF_VERSION" ]; then
	brew install cloudfoundry-cli
	echo $PASSWORD | sudo -S ln -s /usr/local/bin/cf /usr/local/bin/gcf
fi

echo "###### Setting up cf (Create org, spaces) ######"
gcf api --skip-ssl-validation $CLOUD_CONTROLLER_URL
gcf auth $CF_USER $CF_PASSWORD
gcf create-org $ORG_NAME
gcf target -o $ORG_NAME
gcf create-space $SPACE_NAME
gcf target -o $ORG_NAME -s $SPACE_NAME

echo ">>>>>>>>>> End time: $(date) <<<<<<<<<<<<"
echo ">>>>>>>>>> End time: $(date) <<<<<<<<<<<<" >> $LOG_FILE

logSuccess "###### Congratulations: Open Source CloudFoundry setup complete! ######"