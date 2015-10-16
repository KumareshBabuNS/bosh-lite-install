#!/bin/bash

. common.sh

execute_cf_deployment() {
	export_release $CF_RELEASE_DIR/releases cf

	export DEPLOYED_RELEASE=`bosh deployments | grep cf-warden | cut -d '|' -f3 | cut -d '/' -f2 | sort -u`

	if [[ $DEPLOYED_RELEASE != '' ]]; then
		validate_deployed_release $DEPLOYED_RELEASE $CF_LATEST_RELEASE_VERSION false
	else
		export CONTINUE_INSTALL=true
	fi

	if [[ $CONTINUE_INSTALL = true ]]; then
		switch_to_bosh_lite
		set -e
		logTrace "Generate a manifest at manifests/cf-manifest.yml"
		./bin/make_manifest_spiff &> $LOG_FILE 2>&1

		set +e
		generate_and_upload_release $CF_RELEASE_DIR cf $CF_RELEASE

		logInfo "Pointing to the cf-release manifest"
		bosh deployment $BOSH_LITE_DIR/manifests/cf-manifest.yml >> $LOG_FILE 2>&1
		deploy_release $CF_RELEASE_DIR $BOSH_LITE_DIR/manifests/cf-manifest.yml CF

		logSuccess "Done installing $CF_RELEASE"
		echo
	fi
}
