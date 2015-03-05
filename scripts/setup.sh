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
export DIEGO_RELEASE_REPO=https://github.com/cloudfoundry-incubator/diego-release.git

export AWS_STEM_CELL_URL=http://bosh-jenkins-artifacts.s3.amazonaws.com/bosh-stemcell/warden
export STEM_CELL_TO_INSTALL=latest-bosh-stemcell-warden.tgz
export STEM_CELL_URL=$AWS_STEM_CELL_URL/$STEM_CELL_TO_INSTALL

export VAGRANT_VERSION=1.6.5
export RUBY_VERSION=2.1.2

export RVM_DOWNLOAD_URL=https://get.rvm.io

export HOMEBREW_DOWNLOAD_URL=https://raw.github.com/Homebrew/homebrew/go/install

. logMessages.sh

execute() {
	validate_input
	prompt_password
	install_required_tools
	update_repos
	export_cf_release
	download_stemcell
	vagrant_up
	begin_cf_deployment

	echo "Done installing $CF_RELEASE"
	echo

	read -p "Do you want to install diego release? Enter Y/N (N): " DIEGO
	echo

	install_diego $DIEGO

	setup_dev_environment
}

validate_input() {
	set -e
	./validation.sh $PROVIDER
}

prompt_password() {
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
}

install_required_tools() {
	set +e
	$EXECUTION_DIR/ruby_install.sh

	if [[ $OS = "darwin" ]]; then
		set -e
		$EXECUTION_DIR/brew_install.sh

		INSTALLED_WGET=`which wget`
		if [ -z "$INSTALLED_WGET" ]; then
			echo "###### Installing wget ######"
			brew install wget >> $LOG_FILE 2>&1
		fi
	fi

	GO_INSTALLED=`which go`
	if [ -z "$GO_INSTALLED" ]; then
		logError "Go command not found, please install go"
	fi


	BOSH_INSTALLED=`which bosh`
	if [ -z "$BOSH_INSTALLED" ]; then
		logError "Bosh command not found, please fire rvm gemset use bosh-lite"
	fi

	VAGRANT_INSTALLED=`which vagrant`
	if [ -z $VAGRANT_INSTALLED ]; then
		logError "You don't have vagrant Installed. I knew you would never read instructions. Install that first and then come back."
	fi

	PLUGIN_INSTALLED=false
	VMWARE_PLUGIN_INSTALLED=`vagrant plugin list`
	STRING_TO_LOOK_FOR="vagrant-vmware-fusion"
	if echo "$VMWARE_PLUGIN_INSTALLED" | grep -q "$STRING_TO_LOOK_FOR"; then
		PLUGIN_INSTALLED=true
	fi

	INSTALLED_SPIFF=`which spiff`
	if [ -z "$INSTALLED_SPIFF" ]; then
		go get github.com/cloudfoundry-incubator/spiff &> $LOG_FILE 2>&1
	fi
}

update_repos() {
	set -e
	echo "###### Clone Required Git Repositories ######"
	if [ ! -d "$BOSH_LITE_DIR" ]; then
		git clone $BOSH_LITE_REPO $BOSH_LITE_DIR >> $LOG_FILE 2>&1
	fi

	if [[ "$FORCE_DELETE" = "-f" ]]; then
		$EXECUTION_DIR/perform_cleanup.sh
		rm -rf $BOSH_LITE_DIR/$STEM_CELL_TO_INSTALL
	fi

	if [ ! -d "$CF_RELEASE_DIR" ]; then
		git clone $CF_RELEASE_REPO $CF_RELEASE_DIR >> $LOG_FILE 2>&1
	fi

	switch_to_bosh_lite

	set -e
	echo "###### Pull latest changes (if any) for bosh-lite ######"
	git pull >> $LOG_FILE 2>&1

	switch_to_cf_release

	set -e
	echo "###### Update cf-release to sync the sub-modules ######"
	./update &> $LOG_FILE

}

export_cf_release() {
	set -e

	export CF_LATEST_RELEASE_VERSION=`tail -2 $CF_RELEASE_DIR/releases/index.yml | head -1 | cut -d':' -f2 | cut -d' ' -f2`

	if [[ -n ${CF_LATEST_RELEASE_VERSION//[0-9]/} ]]; then
		export CF_LATEST_RELEASE_VERSION=`echo $CF_LATEST_RELEASE_VERSION | tr -d "'"`
	fi

	logInfo "Latest version of Cloud Foundry is: $CF_LATEST_RELEASE_VERSION"
	export CF_RELEASE=cf-$CF_LATEST_RELEASE_VERSION.yml
	logInfo "Deploy CF release $CF_RELEASE"

	echo "###### Validate the entered cf version ######"
	if [ ! -f $CF_RELEASE_DIR/releases/$CF_RELEASE ]; then
		logError "Invalid CF version selected. Please correct and try again"
	fi
}

export_diego_release() {
	set -e

	export DIEGO_LATEST_RELEASE_VERSION=`tail -2 $DIEGO_RELEASE_DIR/releases/index.yml | head -1 | cut -d':' -f2 | cut -d' ' -f2`

	if [[ -n ${DIEGO_LATEST_RELEASE_VERSION//[0-9]/} ]]; then
		export DIEGO_LATEST_RELEASE_VERSION=`echo $DIEGO_LATEST_RELEASE_VERSION | tr -d "'"`
	fi

	logInfo "Latest version of Diego Cloud Foundry is: $DIEGO_LATEST_RELEASE_VERSION"
	export DIEGO_RELEASE=diego-$DIEGO_LATEST_RELEASE_VERSION.yml
	logInfo "Deploy Diego CF release $DIEGO_RELEASE"

	echo "###### Validate the entered diego cf version ######"
	if [ ! -f $DIEGO_RELEASE_DIR/releases/$DIEGO_RELEASE ]; then
		logError "Invalid Diego CF version selected. Please correct and try again"
	fi
}

download_stemcell() {
	switch_to_bosh_lite

	set -e
	echo "###### Download latest warden stemcell ######"
	if [ ! -f $STEM_CELL_TO_INSTALL ]; then
		echo "###### Downloading... warden ######"
		wget --progress=bar:force $STEM_CELL_URL -o $LOG_FILE 2>&1
	else
		echo "###### Warden Stemcell already exists ######"
	fi
}

vagrant_up() {
	switch_to_bosh_lite

	set -e
	echo "###### Vagrant up ######"
	if [ $PROVIDER -eq 1 ]; then
		if [ $PLUGIN_INSTALLED == true ]; then
			logInfo "Found VMWare Fusion plugin, uninstalling it"
			vagrant plugin uninstall vagrant-vmware-fusion
		fi

		vagrant up --provider=virtualbox >> $LOG_FILE 2>&1
	else
		if [ $PLUGIN_INSTALLED == true ]; then
			logInfo "Vagrant Plugin already installed"
		else
			vagrant plugin install vagrant-vmware-fusion >> $LOG_FILE 2>&1
			vagrant plugin license vagrant-vmware-fusion $EXECUTION_DIR/license.lic >> $LOG_FILE 2>&1
		fi

		vagrant up --provider=vmware_fusion >> $LOG_FILE 2>&1
	fi

	echo "###### Target BOSH to BOSH director ######"
	bosh target $BOSH_DIRECTOR_URL

	echo "###### Setup bosh target and login ######"
	bosh login $BOSH_USER $BOSH_PASSWORD

	echo "###### Set the routing tables ######"
	echo $PASSWORD | sudo -S bin/add-route >> $LOG_FILE 2>&1
}

begin_cf_deployment() {
	set +e
	echo "###### Upload stemcell ######"
	bosh upload stemcell --skip-if-exists $BOSH_LITE_DIR/$STEM_CELL_TO_INSTALL >> $LOG_FILE 2>&1

	set -e
	STEM_CELL_NAME=$( bosh stemcells | grep -o "bosh-warden-[^[:space:]]*" )
	echo "###### Uploaded stemcell $STEM_CELL_NAME ######"

	switch_to_cf_release

	set +e
	logCustom 9 "###### Upload cf-release $CF_RELEASE ######"
	bosh upload release releases/$CF_RELEASE &> $LOG_FILE 2>&1

	switch_to_bosh_lite

	set -e
	echo "###### Generate a manifest at manifests/cf-manifest.yml ######"
	./bin/make_manifest_spiff &> $LOG_FILE 2>&1

	echo "###### Deploy the manifest manifests/cf-manifest.yml ######"
	bosh deployment manifests/cf-manifest.yml &> $LOG_FILE 2>&1

	set +e
	logCustom 9 "###### Deploy CF to BOSH-LITE (THIS WOULD TAKE SOME TIME) ######"
	echo "yes" | bosh deploy &> $LOG_FILE 2>&1

	echo "###### Executing BOSH VMS to ensure all VMS are running ######"
	BOSH_VMS_INSTALLED_SUCCESSFULLY=$( bosh vms | grep -o "failing" )
	if [ ! -z "$BOSH_VMS_INSTALLED_SUCCESSFULLY" ]; then
		logError "Not all BOSH VMs are up. Please check logs for more info"
	fi
}

deploy_diego_release() {
	switch_to_diego_release

	set +e
	logCustom 9 "###### Upload diego-release $DIEGO_RELEASE ######"
	bosh deployment $BOSH_RELEASES_DIR/deployments/bosh-lite/diego.yml &> $LOG_FILE 2>&1
	bosh -n upload release &> $LOG_FILE 2>&1

	set +e
	logCustom 9 "###### Deploy Diego to BOSH-LITE (THIS WOULD TAKE SOME TIME) ######"
	echo "yes" | bosh -n deploy &> $LOG_FILE 2>&1
}

setup_dev_environment() {
	$EXECUTION_DIR/setup_cf_commandline.sh
}

switch_to_bosh_lite() {
	set +e
	echo "###### Switching to bosh-lite ######"
	cd $BOSH_LITE_DIR
}

switch_to_cf_release() {
	set +e
	echo "###### Switching to cf-release ######"
	cd $CF_RELEASE_DIR
}

switch_to_diego_release() {
	set +e
	echo "###### Switching to diego-release ######"
	cd $DIEGO_RELEASE_DIR
}

create_deployment_dir() {
	set +e
	echo "###### Create deployment directory ######"
	mkdir -p $BOSH_RELEASES_DIR/deployments/bosh-lite
}

generate_diego_deployment_stub() {
	set +e
	echo "###### Generating Diego deployment stub ######"
	switch_to_diego_release
	./scripts/print-director-stub > $BOSH_RELEASES_DIR/deployments/bosh-lite/director.yml
}

generate_diego_deployment_manifest() {
	set -e
	echo "###### Generating cf release manifest ######"
	switch_to_cf_release
	./generate_deployment_manifest warden $BOSH_RELEASES_DIR/deployments/bosh-lite/director.yml $DIEGO_RELEASE_DIR/templates/enable_diego_docker_in_cc.yml > $BOSH_RELEASES_DIR/deployments/bosh-lite/cf.yml
	switch_to_diego_release
	./scripts/generate-deployment-manifest bosh-lite ../cf-release $BOSH_RELEASES_DIR/deployments/bosh-lite/director.yml > $BOSH_RELEASES_DIR/deployments/bosh-lite/diego.yml
}

generate_diego_release() {
	switch_to_diego_release
	set -e
	echo "###### Create Diego Release ######"
	bosh create release --name diego --force &> $LOG_FILE 2>&1
}

sync_diego_repo() {
	if [ ! -d "$BOSH_RELEASES_DIR/diego-release" ]; then
		git clone $DIEGO_RELEASE_REPO $BOSH_RELEASES_DIR/diego-release >> $LOG_FILE 2>&1
	fi

	set -e
	switch_to_diego_release
	echo "###### Update diego-release to sync the sub-modules ######"
	./scripts/update &> $LOG_FILE
}

install_diego() {
	if [[ $1 = "Y" || $1 = "y" ]]; then
		echo "###### Installing Diego ######"
		sync_diego_repo
		export_diego_release
		generate_diego_release
		create_deployment_dir
		generate_diego_deployment_stub
		generate_diego_deployment_manifest
		generate_diego_release
		echo "###### Deploy the manifest for diego ######"
		bosh deployment $BOSH_RELEASES_DIR/deployments/bosh-lite/cf.yml
		deploy_diego_release
		echo "###### Deploy installing $DIEGO_RELEASE ######"
	fi
}

echo "######  Install Open Source CloudFoundry ######"
if [ $# -lt 2 ]; then
	echo "Usage: ./setup.sh <provider> <install-dir> <options>"
	printf "\t %s \t\t %s \n\t\t\t\t %s \n" "provider:" "Enter 1 for Virtual Box" "Enter 2 for VMWare Fusion"
	printf "\t %s \t\t %s \n" "install-dir:" "Specify the install directory"
	printf "\t %s \t\t\t %s \n" "-f" "Force remove old installation and install fresh"
	exit 1
fi

if [ ! -d $2 ]; then
	logError "Non-existant directory: $2"
fi

export PROVIDER=$1
export BOSH_RELEASES_DIR=$2

if [[ $3 = "-f" ]]; then
	export FORCE_DELETE="-f"
fi

export OS=`uname`

export BOSH_LITE_DIR=$BOSH_RELEASES_DIR/bosh-lite
export CF_RELEASE_DIR=$BOSH_RELEASES_DIR/cf-release
export DIEGO_RELEASE_DIR=$BOSH_RELEASES_DIR/diego-release

execute

echo ">>>>>>>>>> End time: $(date) <<<<<<<<<<<<"
echo ">>>>>>>>>> End time: $(date) <<<<<<<<<<<<" >> $LOG_FILE

logSuccess "###### Congratulations: Open Source CloudFoundry setup complete! ######"
