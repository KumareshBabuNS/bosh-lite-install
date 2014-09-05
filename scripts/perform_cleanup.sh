#!/bin/bash --login
. logMessages.sh

set +e
echo "###### Switching to bosh-lite ######"
cd $BOSH_RELEASES_DIR/bosh-lite

logInfo "Deleting vagrant box"
vagrant halt local
vagrant destroy local -f

logSuccess "Deleted your old vagrant box, and continuing setup"
