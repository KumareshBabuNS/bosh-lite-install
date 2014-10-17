#!/bin/bash

export CF_USER=admin
export CF_PASSWORD=admin
export CLOUD_CONTROLLER_URL=https://api.10.244.0.34.xip.io/
export ORG_NAME=local
export SPACE_NAME=development

export EXECUTION_DIR=$PWD
export LOG_FILE=$EXECUTION_DIR/setup.log

echo "###### Setup cloudfoundry cli ######"
GO_CF_VERSION=`which cf`
if [ -z "$GO_CF_VERSION" ]; then
  brew tap pivotal/tap >> $LOG_FILE 2>&1
  brew install cloudfoundry-cli >> $LOG_FILE 2>&1
fi

set -e
echo "###### Setting up cf (Create org, spaces) ######"
cf api --skip-ssl-validation $CLOUD_CONTROLLER_URL >> $LOG_FILE 2>&1
cf auth $CF_USER $CF_PASSWORD >> $LOG_FILE 2>&1
cf create-org $ORG_NAME >> $LOG_FILE 2>&1
cf target -o $ORG_NAME >> $LOG_FILE 2>&1
cf create-space $SPACE_NAME >> $LOG_FILE 2>&1
cf target -o $ORG_NAME -s $SPACE_NAME >> $LOG_FILE 2>&1
