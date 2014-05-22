#!/bin/bash

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

export REQUIRED_RUBY_VERSION=1.9.3-p484
export EXPECTED_RUBY_VERSION="1.9.3"

export VAGRANT_VERSION=1.6.2

export RVM_DOWNLOAD_URL=https://get.rvm.io
export VAGRANT_DOWNLOAD_URL=http://d29vzk4ow07wi7.cloudfront.net/6bc40bf82eec0e266fce9f7ab3aafaf82624a7f0?response-content-disposition=attachment%3Bfilename%3D%22vagrant_1.6.2.dmg%22&Policy=eyJTdGF0ZW1lbnQiOiBbeyJSZXNvdXJjZSI6Imh0dHAqOi8vZDI5dnprNG93MDd3aTcuY2xvdWRmcm9udC5uZXQvNmJjNDBiZjgyZWVjMGUyNjZmY2U5ZjdhYjNhYWZhZjgyNjI0YTdmMD9yZXNwb25zZS1jb250ZW50LWRpc3Bvc2l0aW9uPWF0dGFjaG1lbnQlM0JmaWxlbmFtZSUzRCUyMnZhZ3JhbnRfMS42LjIuZG1nJTIyIiwiQ29uZGl0aW9uIjp7IkRhdGVMZXNzVGhhbiI6eyJBV1M6RXBvY2hUaW1lIjoxNDAwNzkzNjI2fSwiSXBBZGRyZXNzIjp7IkFXUzpTb3VyY2VJcCI6IjAuMC4wLjAvMCJ9fX1dfQ__&Signature=OYEpYhdsIC363HC4X0eMwKGTljPfRtNsmmlDOR0zf6d41oUmFhkqhSxdiv6jb7RDw3SmbnrjBKvHuHGhZ1Yv~~hs3AJKx6pd~zzyPL9yaGaJ8lyOqRcsZO9rbycVdZtdQAPF6fHFzvzlvxAjtCPfNK09dF0eptmdKQm~5~nNCsRZmOz~Pqm20U4iFibszU343cikpa4X2Udsbmif21D2yg93qvHnmMaOwg~vaEDmwTKv3bCcbHNcw4Kf4xM662Hcuj8cs9oXCfCsPXENuw5YvxoBhV4wGBfrhnBUu34mYfR44ybYSuDe8l0XG9Je7dPCuQa0~TyEkBOYDmhNh7Y7fw__&Key-Pair-Id=APKAIQIOJCQ5764M5VTQ
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

if [[ -n ${1//[0-9]/} ]]; then
	logError "Invalid cf version number, please try again"
fi

if [ $2 -eq 1 ] || [ $2 -eq 2 ]; then
	if [ $2 -eq 1 ]; then 
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
			logError ERROR_MSG INFO_MSG
		fi
	fi
else
	logError "Please provide the valid selection for the provider"
fi

read -s -p "Enter Password: " PASSWORD
if [ -z $PASSWORD ]; then
	logError "Please provide the sudo password"
fi

echo

if [ ! -f "$BOSH_RELEASES_DIR/login.sh" ]; then
	ERROR_MSG="Dude you don't read instructions"
	INFO_MSG="Place the login.sh file under $BOSH_RELEASES_DIR/"
	logError ERROR_MSG INFO_MSG
fi

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

./brew_install.sh $OS $PASSWORD

export CF_RELEASE=cf-$1.yml
logInfo "Deploy CF release" $CF_RELEASE

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

echo "###### Install RVM and download the appropriate version of Ruby ######"
RUBY_VERSION_INSTALLED=`ruby -v`

if echo "$RUBY_VERSION_INSTALLED" | grep -q "$EXPECTED_RUBY_VERSION"; then
	logInfo "Ruby RubyGems Already Installed"
else	
	\curl -sSL $RVM_DOWNLOAD_URL | bash >> $LOG_FILE 2>&1
	if [ $? -gt 0 ]; then
		echo $PASSWORD | \curl -sSL $RVM_DOWNLOAD_URL | sudo bash >> $LOG_FILE 2>&1
	fi
	`source ~/.rvm/scripts/rvm`
	`type rvm | head -n 1`
	
	WHICH_RVM=`which rvm`
	if [ -z $WHICH_RVM ]; then
		logInfo "Installed RVM now, please close this terminal and open a new terminal"
		logInfo "Fire the setup.sh again"
		exit 1		
	fi
	
	rvm install $REQUIRED_RUBY_VERSION >> $LOG_FILE 2>&1
	if [ $? -gt 0 ]; then
		echo $PASSWORD | sudo -S rvm install $REQUIRED_RUBY_VERSION >> $LOG_FILE 2>&1
	fi
	
	if [ $? -gt 0 ]; then
		logError "Unable to Install ruby"
	fi	
fi	

echo "###### Using Ruby $REQUIRED_RUBY_VERSION ######"
rvm use $REQUIRED_RUBY_VERSION --default

echo "###### Installing Bundler ######"
INSTALLED_BUNDLE_VERSION=`which bundle` >> $LOG_FILE 2>&1
if [ -z $INSTALLED_BUNDLE_VERSION ]; then
	gem install bundler >> $LOG_FILE 2>&1
	logInfo "Installed bundler"
	if [ $? -gt 0 ]; then
		echo $PASSWORD | sudo -S gem install bundler >> $LOG_FILE 2>&1
	fi
	
	if [ $? -gt 0 ]; then
		logError "Unable to Install bundler"
	fi
	
fi

echo "###### Installing wget ######"
brew install wget >> $LOG_FILE 2>&1

echo "###### Install spiff ######"
brew tap xoebus/homebrew-cloudfoundry
brew install spiff &> $LOG_FILE 2>&1

cd $BOSH_RELEASES_DIR/bosh-lite

echo "###### Pull latest changes (if any) for bosh-lite ######"
git pull >> $LOG_FILE 2>&1

echo "###### Download warden ######"
if [ ! -f $STEM_CELL_TO_INSTALL ]; then
    echo "###### Downloading... warden ######"
    wget $STEM_CELL_URL -o $LOG_FILE 2>&1
else 
	logInfo "Skipping warden download, local copy exists"
fi

echo "###### Bundle bosh-lite ######"
bundle &> $LOG_FILE 2>&1

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

set +e

rvm gemset use bosh-lite

echo "###### Target BOSH to BOSH director ######"
bosh target $BOSH_DIRECTOR_URL

echo "###### Setup bosh target and login ######"
bosh login $BOSH_USER $BOSH_PASSWORD

echo "###### Set the routing tables ######"
echo $PASSWORD | sudo -S scripts/add-route >> $LOG_FILE 2>&1

echo "###### Upload stemcell ######"
bosh upload stemcell $BOSH_RELEASES_DIR/bosh-lite/$STEM_CELL_TO_INSTALL >> $LOG_FILE 2>&1

STEM_CELL_NAME=$( bosh stemcells | grep -o "bosh-warden-[^[:space:]]*" )
echo "###### Uploaded stemcell $STEM_CELL_NAME ######"

echo "###### Update cf-release repo ######"
cd $BOSH_RELEASES_DIR/cf-release
./update &> $LOG_FILE

rvm gemset use bosh-lite
echo "###### Bundle cf-release ######"
bundle &> $LOG_FILE 2>&1

echo "###### Upload cf-release" $CF_RELEASE "######"
bosh upload release releases/$CF_RELEASE &> $LOG_FILE 2>&1

echo "###### Generate a manifest at manifests/cf-manifest.yml ######"
cd $BOSH_RELEASES_DIR/bosh-lite
./scripts/make_manifest_spiff &> $LOG_FILE 2>&1

echo "###### Deploy the manifest manifests/cf-manifest.yml ######"
bosh deployment manifests/cf-manifest.yml &> $LOG_FILE 2>&1

#sed -i.bak 's/bosh-warden-boshlite-ubuntu/'"$STEM_CELL_NAME"'/' $PWD/manifests/cf-manifest.yml

logCustom 9 "###### Deploy CF to BOSH-LITE (THIS WOULD TAKE SOME TIME) ######"
echo "yes" | bosh deploy &> $LOG_FILE 2>&1

echo "###### Executing BOSH VMS to ensure all VMS are running ######"
BOSH_VMS_INSTALLED_SUCCESSFULLY=$( bosh vms | grep -o "failing" )
if [ ! -z $BOSH_VMS_INSTALLED_SUCCESSFULLY]; then
	logError "Not all BOSH VMs are up. Please check logs for more info"
fi

echo "###### Setup cloudfoundry cli ######"
GO_CF_VERSION=`which gcf`
if [ -z $GO_CF_VERSION ]; then
	brew install cloudfoundry-cli
fi

echo $PASSWORD | sudo -S ln -s /usr/local/bin/cf /usr/local/bin/gcf

set -e

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