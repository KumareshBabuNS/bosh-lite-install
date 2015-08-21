#!/bin/bash

. common.sh

sync_diego_repo() {
	if [ ! -d "$BOSH_RELEASES_DIR/diego-release" ]; then
		git clone $DIEGO_RELEASE_REPO $BOSH_RELEASES_DIR/diego-release >> $LOG_FILE 2>&1
	fi

	set -e
	switch_to_diego_release
	echo "###### Update diego-release to sync the sub-modules ######"
	./scripts/update &> $LOG_FILE
}

sync_garden_repo() {
	if [ ! -d "$BOSH_RELEASES_DIR/garden-linux-release" ]; then
		git clone $GARDEN_RELEASE_REPO $BOSH_RELEASES_DIR/garden-linux-release >> $LOG_FILE 2>&1
	fi

	set -e
	switch_to_garden_linux_release
	echo "###### Update garden-linux-release to sync the sub-modules ######"
	git pull &> $LOG_FILE

	bundle install &> $LOG_FILE
}

export_diego_release() {
	set -e

	if [ -z $DIEGO_VERSION_REQUIRED ]; then
		export DIEGO_LATEST_RELEASE_VERSION=`tail -2 $DIEGO_RELEASE_DIR/releases/index.yml | head -1 | cut -d':' -f2 | cut -d' ' -f2`

		if [[ -n ${DIEGO_LATEST_RELEASE_VERSION//[0-9]/} ]]; then
			export DIEGO_LATEST_RELEASE_VERSION=`echo $DIEGO_LATEST_RELEASE_VERSION | tr -d "'"`
		fi
	else
		export DIEGO_LATEST_RELEASE_VERSION=$DIEGO_VERSION_REQUIRED
	fi

	logInfo "Latest version of Diego Cloud Foundry is: $DIEGO_LATEST_RELEASE_VERSION"
	export DIEGO_RELEASE=diego-$DIEGO_LATEST_RELEASE_VERSION.yml
	logInfo "Deploy Diego CF release $DIEGO_RELEASE"

	echo "###### Validate the entered diego cf version ######"
	if [ ! -f $DIEGO_RELEASE_DIR/releases/$DIEGO_RELEASE ]; then
		logError "Invalid Diego CF version selected. Please correct and try again"
	fi
}

export_garden_linux_release() {
	set -e

	if [ -z $DIEGO_VERSION_REQUIRED ]; then
		export GARDEN_LINUX_LATEST_RELEASE_VERSION=`tail -2 $GARDEN_RELEASE_DIR/releases/garden-linux/index.yml | head -1 | cut -d':' -f2 | cut -d' ' -f2`

		if [[ -n ${GARDEN_LINUX_LATEST_RELEASE_VERSION//[0-9]/} ]]; then
			export GARDEN_LINUX_LATEST_RELEASE_VERSION=`echo $GARDEN_LINUX_LATEST_RELEASE_VERSION | tr -d "'"`
		fi
	else
		export GARDEN_LINUX_LATEST_RELEASE_VERSION=$GARDEN_LINUX_LATEST_RELEASE_VERSION
	fi

	logInfo "Latest version of Garden Linux is: $GARDEN_LINUX_LATEST_RELEASE_VERSION"
	export GARDEN_LINUX_RELEASE=garden-linux-$GARDEN_LINUX_LATEST_RELEASE_VERSION.yml
	logInfo "Deploy Garden Linux version $GARDEN_LINUX_RELEASE"

	echo "###### Validate the entered garden linux version ######"
	if [ ! -f $GARDEN_RELEASE_DIR/releases/garden-linux/$GARDEN_LINUX_RELEASE ]; then
		logError "Invalid garden linux version selected. Please correct and try again"
	fi
}

execute_diego_deployment() {
	echo "###### Installing Diego ######"
	sync_diego_repo
	sync_garden_repo
	export_cf_release
	export_diego_release
	export_garden_linux_release

	export DEPLOYED_RELEASE=`bosh deployments | grep diego/ | cut -d '|' -f3 | cut -d '/' -f2 | cut -d '+' -f1 | sort -u`

	if [[ $DEPLOYED_RELEASE != '' ]]; then
		validate_deployed_release $DEPLOYED_RELEASE $DIEGO_LATEST_RELEASE_VERSION true
	else
		export CONTINUE_INSTALL=true
	fi

	if [[ $CONTINUE_INSTALL = true ]]; then
		create_deployment_dir

		generate_diego_deployment_stub
		generate_diego_deployment_manifest
		bosh deployment $BOSH_RELEASES_DIR/deployments/bosh-lite/cf.yml &> $LOG_FILE 2>&1
		switch_to_cf_release
		generate_and_upload_release $CF_RELEASE_DIR cf $CF_RELEASE
		echo "###### Deploy cf release ######"
		deploy_release $CF_RELEASE_DIR $BOSH_RELEASES_DIR/deployments/bosh-lite/cf.yml CF

		bosh deployment $BOSH_RELEASES_DIR/deployments/bosh-lite/diego.yml &> $LOG_FILE 2>&1

		switch_to_garden_linux_release
		generate_and_upload_release $GARDEN_RELEASE_DIR garden-linux garden-linux/$GARDEN_LINUX_RELEASE

		generate_and_upload_release $DIEGO_RELEASE_DIR diego $DIEGO_RELEASE
		echo "###### Deploy diego release ######"
		deploy_release $DIEGO_RELEASE_DIR $BOSH_RELEASES_DIR/deployments/bosh-lite/diego.yml DIEGO
		echo "###### Done Deploying installing $DIEGO_RELEASE ######"
	fi
}
