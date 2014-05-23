logError () {
	logCustom 1 "ERROR: $1"
	
	if [[ ! -z "$2" ]]; then
		logInfo "$2"
	fi	

	echo ">>>>>>>>>> End time: $(date) <<<<<<<<<<<<"
	exit 1
}

logSuccess () {
	logCustom 2 "SUCCESS: $1"	
}

logInfo () {
	logCustom 3 "INFO: $1"
}

logCustom () {
	tput setaf $1
	echo "$2"
	tput sgr 0	
}