Scripts to install bosh-lite on your local machine

Clone this repository -> git clone https://github.com/pivotalservices/bosh-lite-install.git bosh-lite-install.

Once done, copy all the shell (.sh) files from scripts folder to any directory of your choice. 

Ensure the script has executable permissions. If not -> chmod +x setup.sh

Before you fire the script, please ensure you have brew install. Refer to http://brew.sh/ for details.

Install [Vagrant] (http://www.vagrantup.com/)

Install [VirtualBox] (https://www.virtualbox.org/) if you don't have [VMWare Fusion] (http://www.vmware.com/products/fusion-professional)

If you setup with VMWare fusion provider, you might be prompted to enter you password again. Sorry, but this will be fixed soon.

You would see the following output once you execute the script -> ./setup.sh

Install Open Source CloudFoundry

```
######  Install Open Source CloudFoundry ######
Usage: ./setup.sh <cf-release-version> <provider>
	 cf-release-version: 	 Cloud foundry version to deploy on vagrant 
	 provider: 		         Enter 1 for Virtual Box 
							 Enter 2 for VMWare Fusion 

```

ex: ./setup.sh 172 1

Enter the password when prompted for.

Logs are located in the same directory -> setup.log

This is work in progress! Enjoy!!

What happens in the script:
* Git pull of bosh-lite and cf-release
* Installs homebrew if its missing
* Installs rvm, ruby if its missing
* Start the VM with the ubuntu box that's packaged with BOSH 
* Latest stemcell is installed into the VM
* Release build is installed into the VM
* Finally cf release is deployed into the VM
* Once all the steps are executed, the CF command cli is installed and the CLI is targetted to your new setup
* New org, spaces are created

Troubleshooting:
If the script fails due to any reason, look at the errors in the setup.log
* If starting of any bosh jobs fail to start at the end of the script, run `bosh vms`
* Look for the Job/s which have the status as failing
* Run `bosh restart <job-name>`

