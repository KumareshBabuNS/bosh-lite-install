#!/bin/bash --login

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
export GARDEN_RELEASE_REPO=https://github.com/cloudfoundry-incubator/garden-linux-release.git

export AWS_STEM_CELL_URL=http://bosh-jenkins-artifacts.s3.amazonaws.com/bosh-stemcell/warden
export STEM_CELL_TO_INSTALL=latest-bosh-stemcell-warden.tgz
export STEM_CELL_URL=$AWS_STEM_CELL_URL/$STEM_CELL_TO_INSTALL

export VAGRANT_VERSION=1.7.4
export BOSH_RUBY_VERSION=2.2.3

export RVM_DOWNLOAD_URL=https://get.rvm.io

export HOMEBREW_DOWNLOAD_URL=https://raw.github.com/Homebrew/homebrew/go/install

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

	if [[ $OS = "Darwin" ]]; then
		set +e
		$EXECUTION_DIR/brew_install.sh

		INSTALLED_WGET=`which wget`
		if [ -z $INSTALLED_WGET ]; then
			echo "###### Installing wget ######"
			brew install wget >> $LOG_FILE 2>&1
		fi
	fi

	GO_INSTALLED=`which go`
	if [ -z $GO_INSTALLED ]; then
		logInfo "Go command not found, please install go"
		brew install go >> $LOG_FILE 2>&1
	fi


	BOSH_INSTALLED=`which bosh`
	if [ -z $BOSH_INSTALLED ]; then
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
	if [ -z $INSTALLED_SPIFF ]; then
		go get github.com/cloudfoundry-incubator/spiff &> $LOG_FILE 2>&1
	fi
}

update_repos() {
	set -e
	echo "###### Clone Required Git Repositories ######"
	if [ ! -d $BOSH_LITE_DIR ]; then
		git clone $BOSH_LITE_REPO $BOSH_LITE_DIR >> $LOG_FILE 2>&1
	fi

	if [[ $FORCE_DELETE = "-f" ]]; then
		$EXECUTION_DIR/perform_cleanup.sh
		#rm -rf $BOSH_LITE_DIR/$STEM_CELL_TO_INSTALL
	fi

	if [ ! -d $CF_RELEASE_DIR ]; then
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

switch_to_garden_linux_release() {
	set +e
	echo "###### Switching to garden-linux-release ######"
	cd $GARDEN_RELEASE_DIR
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
	./generate_deployment_manifest warden \
		$BOSH_RELEASES_DIR/deployments/bosh-lite/director.yml \
		$DIEGO_RELEASE_DIR/stubs-for-cf-release/enable_consul_with_cf.yml \
		$DIEGO_RELEASE_DIR/stubs-for-cf-release/enable_diego_windows_in_cc.yml \
		$DIEGO_RELEASE_DIR/stubs-for-cf-release/enable_diego_ssh_in_cf.yml \
		> $BOSH_RELEASES_DIR/deployments/bosh-lite/cf.yml

	switch_to_diego_release
	./scripts/generate-deployment-manifest $BOSH_RELEASES_DIR/deployments/bosh-lite/director.yml \
		$DIEGO_RELEASE_DIR/manifest-generation/bosh-lite-stubs/property-overrides.yml \
		$DIEGO_RELEASE_DIR/manifest-generation/bosh-lite-stubs/instance-count-overrides.yml \
		$DIEGO_RELEASE_DIR/manifest-generation/bosh-lite-stubs/persistent-disk-overrides.yml \
		$DIEGO_RELEASE_DIR/manifest-generation/bosh-lite-stubs/iaas-settings.yml \
		$DIEGO_RELEASE_DIR/manifest-generation/bosh-lite-stubs/additional-jobs.yml \
		$BOSH_RELEASES_DIR/deployments/bosh-lite \
		> $BOSH_RELEASES_DIR/deployments/bosh-lite/diego.yml
}

generate_and_upload_release() {
	cd $1
	logCustom 9 "###### Upload $2-release $3 ######"
	bosh -n upload release releases/$3 >> $LOG_FILE 2>&1
}

deploy_release() {
	cd $1

	set +e
	bosh deployment $2 &> $LOG_FILE 2>&1

	set +e
	logCustom 9 "###### Deploy $3 to BOSH-LITE (THIS WOULD TAKE SOME TIME) ######"
	bosh -n deploy &> $LOG_FILE 2>&1
}

validate_deployed_release() {
	set -e
	export CONTINUE_INSTALL=true

	echo "Deployed version " $1 " and new version " $2
	if [[ $1 != '' ]]; then
		if [[ "$1" = "$2" ]]; then
			logInfo "You're already on the current version, skipping deployment"
			export CONTINUE_INSTALL=false
		else
			logInfo "New CF release available, undeploying the older version"
			# Check if Diego Release
			if [[ $3 = true ]]; then
				bosh -n delete deployment cf-warden-diego --force &> $LOG_FILE 2>&1
				bosh -n delete release diego --force &> $LOG_FILE 2>&1
				bosh -n delete release garden-linux --force &> $LOG_FILE 2>&1
			fi
			bosh -n delete deployment cf-warden --force &> $LOG_FILE 2>&1
			bosh -n delete release cf --force &> $LOG_FILE 2>&1
			export RETAKE_SNAPSHOT=true
		fi
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

			vagrant plugin install vagrant-multiprovider-snap >> $LOG_FILE 2>&1
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

download_and_upload_stemcell() {
	switch_to_bosh_lite

	set -e
	echo "###### Download latest warden stemcell ######"
	if [ ! -f $STEM_CELL_TO_INSTALL ]; then
		echo "###### Downloading... warden ######"
		wget --progress=bar:force $STEM_CELL_URL -o $LOG_FILE 2>&1
	else
		echo "###### Warden Stemcell already exists ######"
	fi

	set +e
	echo "###### Upload stemcell ######"
	bosh upload stemcell --skip-if-exists $BOSH_LITE_DIR/$STEM_CELL_TO_INSTALL >> $LOG_FILE 2>&1

	set -e
	STEM_CELL_NAME=$( bosh stemcells | grep -o "bosh-warden-[^[:space:]]*" )
	echo "###### Uploaded stemcell $STEM_CELL_NAME ######"
}

pre_install() {
	validate_input
	prompt_password
	install_required_tools
	update_repos
	vagrant_up
	download_and_upload_stemcell
}

setup_dev_environment() {
	$EXECUTION_DIR/setup_cf_commandline.sh
}

post_install_activities() {
	echo "###### Executing BOSH VMS to ensure all VMS are running ######"
	BOSH_VMS_INSTALLED_SUCCESSFULLY=$( bosh vms | grep -o "failing" )
	if [ ! -z "$BOSH_VMS_INSTALLED_SUCCESSFULLY" ]; then
		logError "Not all BOSH VMs are up. Please check logs for more info"
	fi

	setup_dev_environment

	if [[ $SELECTION = 2 ]]; then
		cf enable-feature-flag diego_docker
	fi

	cd $BOSH_LITE_DIR

	if [[ $CONTINUE_INSTALL = true ]]; then
		IS_VAGRANT_SNAPSHOT_PLUGIN_AVAILABLE=`vagrant plugin list | grep vagrant-multiprovider-snap`
		if [[ $IS_VAGRANT_SNAPSHOT_PLUGIN_AVAILABLE != '' ]]; then
			if [[ $RETAKE_SNAPSHOT = true ]]; then
				vagrant snap delete --name=original
			fi
			vagrant snap take --name=original
		fi
	fi
}
