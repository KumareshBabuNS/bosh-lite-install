#!/bin/bash
. logMessages.sh

export CF_USER=admin
export CF_PASSWORD=admin
export CLOUD_CONTROLLER_URL=https://api.10.244.0.34.xip.io/
export ORG_NAME=local
export SPACE_NAME=development

set -e
echo "###### Setup cloudfoundry cli ######"
GO_CF_VERSION=`which cf`
if [ -z "$GO_CF_VERSION" ]; then
  brew install cloudfoundry-cli
#	echo $PASSWORD | sudo -S ln -s /usr/local/bin/cf /usr/local/bin/gcf
fi

echo "###### Setting up cf (Create org, spaces) ######"
cf api --skip-ssl-validation $CLOUD_CONTROLLER_URL
cf auth $CF_USER $CF_PASSWORD
cf create-org $ORG_NAME
cf target -o $ORG_NAME
cf create-space $SPACE_NAME
cf target -o $ORG_NAME -s $SPACE_NAME
