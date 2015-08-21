#!/bin/bash

. common.sh

export_cf_release() {
	set -e

	if [ -z $CF_VERSION_REQUIRED ]; then
		export CF_LATEST_RELEASE_VERSION=`tail -2 $CF_RELEASE_DIR/releases/index.yml | head -1 | cut -d':' -f2 | cut -d' ' -f2`

		if [[ -n ${CF_LATEST_RELEASE_VERSION//[0-9]/} ]]; then
			export CF_LATEST_RELEASE_VERSION=`echo $CF_LATEST_RELEASE_VERSION | tr -d "'"`
		fi
	else
		export CF_LATEST_RELEASE_VERSION=$CF_VERSION_REQUIRED
	fi

	logInfo "Latest version of Cloud Foundry is: $CF_LATEST_RELEASE_VERSION"
	export CF_RELEASE=cf-$CF_LATEST_RELEASE_VERSION.yml
	logInfo "Deploy CF release $CF_RELEASE"

	echo "###### Validate the entered cf version ######"
	if [ ! -f $CF_RELEASE_DIR/releases/$CF_RELEASE ]; then
		logError "Invalid CF version selected. Please correct and try again"
	fi
}

begin_cf_deployment() {
	logInfo "###### Poiting to the cf-release manifest ######"
	bosh deployment $BOSH_LITE_DIR/manifests/cf-manifest.yml >> $LOG_FILE 2>&1

	switch_to_cf_release
	set +e
	logCustom 9 "###### Upload cf-release $CF_RELEASE ######"
	bosh upload release releases/$CF_RELEASE &> $LOG_FILE 2>&1

	set +e
	logCustom 9 "###### Deploy $3 to BOSH-LITE (THIS WOULD TAKE SOME TIME) ######"
	bosh -n deploy &> $LOG_FILE 2>&1
}

execute_cf_deployment() {
	export_cf_release

	export DEPLOYED_RELEASE=`bosh deployments | grep cf-warden | cut -d '|' -f3 | cut -d '/' -f2 | sort -u`

	if [[ $DEPLOYED_RELEASE != '' ]]; then
		validate_deployed_release $DEPLOYED_RELEASE $CF_LATEST_RELEASE_VERSION false
	else
		export CONTINUE_INSTALL=true
	fi

	if [[ $CONTINUE_INSTALL = true ]]; then
		switch_to_bosh_lite
		set -e
		echo "###### Generate a manifest at manifests/cf-manifest.yml ######"
		./bin/make_manifest_spiff &> $LOG_FILE 2>&1

		begin_cf_deployment
		echo "Done installing $CF_RELEASE"
		echo
	fi
}
