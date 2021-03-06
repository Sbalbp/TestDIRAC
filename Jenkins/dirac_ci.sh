#!/bin/sh 
#-------------------------------------------------------------------------------
# dirac_ci
#
#  Several functions used for Jenkins style jobs
#
#
# fstagni@cern.ch  
# 09/12/2014
#-------------------------------------------------------------------------------

# first first: sourcing utility file
source $WORKSPACE/TestDIRAC/Jenkins/utilities.sh


############################################
# List URLs where to get scripts
############################################
DIRAC_INSTALL='https://github.com/DIRACGrid/DIRAC/raw/integration/Core/scripts/dirac-install.py'
DIRAC_PILOT='https://raw.githubusercontent.com/DIRACGrid/DIRAC/integration/WorkloadManagementSystem/PilotAgent/dirac-pilot.py'
DIRAC_PILOT_TOOLS='https://raw.githubusercontent.com/DIRACGrid/DIRAC/integration/WorkloadManagementSystem/PilotAgent/pilotTools.py'
DIRAC_PILOT_COMMANDS='https://raw.githubusercontent.com/DIRACGrid/DIRAC/integration/WorkloadManagementSystem/PilotAgent/pilotCommands.py'
DIRAC_INSTALL_SITE='https://github.com/DIRACGrid/DIRAC/raw/integration/Core/scripts/install_site.sh --no-check-certificate'

DIRAC_RELEASES='https://raw.githubusercontent.com/DIRACGrid/DIRAC/integration/releases.cfg'
############################################

INSTALL_CFG_FILE='$WORKSPACE/TestDIRAC/Jenkins/install.cfg'


#...............................................................................
#
# installSite:
#
#   This function will install DIRAC using the install_site.sh script 
#     following (more or less) instructions at diracgrid.org
#
#...............................................................................

function installSite(){
	echo '[installSite]'
	 
	killRunsv
	findRelease

	generateCertificates

	#install_site.sh file
	mkdir $WORKSPACE/DIRAC
	cd $WORKSPACE/DIRAC
	wget -np $DIRAC_INSTALL_SITE
	chmod +x install_site.sh
	
	#Fixing install.cfg file
	cp $(eval echo $INSTALL_CFG_FILE) .
	sed -i s/VAR_Release/$projectVersion/g $WORKSPACE/DIRAC/install.cfg
	sed -i s/VAR_LcgVer/$externalsVersion/g $WORKSPACE/DIRAC/install.cfg
	sed -i s,VAR_TargetPath,$WORKSPACE,g $WORKSPACE/DIRAC/install.cfg
	fqdn=`hostname --fqdn`
	sed -i s,VAR_HostDN,$fqdn,g $WORKSPACE/DIRAC/install.cfg
	
	sed -i s/VAR_DB_User/$DB_USER/g $WORKSPACE/DIRAC/install.cfg
	sed -i s/VAR_DB_Password/$DB_PASSWORD/g $WORKSPACE/DIRAC/install.cfg
	sed -i s/VAR_DB_RootUser/$DB_ROOTUSER/g $WORKSPACE/DIRAC/install.cfg
	sed -i s/VAR_DB_RootPwd/$DB_ROOTPWD/g $WORKSPACE/DIRAC/install.cfg
	sed -i s/VAR_DB_Host/$DB_HOST/g $WORKSPACE/DIRAC/install.cfg
	sed -i s/VAR_DB_Port/$DB_PORT/g $WORKSPACE/DIRAC/install.cfg
	
	#Installing
	./install_site.sh install.cfg
	
	source $WORKSPACE/bashrc
}


#...............................................................................
#
# fullInstall:
#
#   This function install all the DIRAC stuff known...
#
#...............................................................................

function fullInstallDIRAC(){
	echo '[fullInstallDIRAC]'
	
	finalCleanup
	
	if [ ! -z "$DEBUG" ]
	then
		echo 'Running in DEBUG mode'
		export DEBUG='-ddd'
	fi  
	
	#basic install, with only the CS running 
	installSite
	
	#replace the sources with custom ones if defined
	diracReplace
	
	#Dealing with security stuff
	generateUserCredentials
	diracCredentials
	
	#just add a site
	diracAddSite
	
	#Install the Framework
	findDatabases 'FrameworkSystem'
	dropDBs
	diracDBs
	findServices 'FrameworkSystem'
	diracServices
	
	#create groups
	diracUserAndGroup
	
	#Now all the rest	
	
	#DBs (not looking for FrameworkSystem ones, already installed)
	#findDatabases 'exclude' 'FrameworkSystem'
	findDatabases 'exclude' 'FrameworkSystem'
	dropDBs
	diracDBs

	diracDFCDB
	
	#fix the DBs 
	python $WORKSPACE/TestDIRAC/Jenkins/dirac-cfg-update-dbs.py $WORKSPACE $DEBUG
	#refresh the configuration (gConfig dark side!)
	sleep 10
	#diracRefreshCS
	sleep 10
	#echo 'Restarting Configuration Server'
	dirac-restart-component Configuration Server $DEBUG
	sleep 30
	
	#services (not looking for FrameworkSystem already installed)
	#findServices 'exclude' 'FrameworkSystem'
	findServices 'exclude' 'FrameworkSystem'
	diracServices

	#fix the services 
	python $WORKSPACE/TestDIRAC/Jenkins/dirac-cfg-update-services.py $WORKSPACE $DEBUG
	#refresh the configuration (gConfig dark side!)
	sleep 10
	diracRefreshCS
	sleep 10
	echo 'Restarting Configuration Server'
	dirac-restart-component Configuration Server $DEBUG
	sleep 30
	
	#fix the SandboxStore 
	python $WORKSPACE/TestDIRAC/Jenkins/dirac-cfg-update-server.py $WORKSPACE $DEBUG
	#refresh the configuration (gConfig dark side!)
	sleep 10
	diracRefreshCS
	sleep 10
	echo 'Restarting Configuration Server'
	dirac-restart-component Configuration Server $DEBUG
	sleep 30
	echo 'Restarting WorkloadManagement SandboxStore'
	dirac-restart-component WorkloadManagement SandboxStore $DEBUG

	dirac-restart-component DataManagement FileCatalog $DEBUG

	#refresh the configuration (gConfig dark side!)
	sleep 10
	
	#upload proxies
	diracProxies
	# prod
}




############################################
# Pilot
############################################

#...............................................................................
#
# MAIN function: DIRACPilotInstall:
#
#   This function uses the pilot code to make a DIRAC pilot installation
#   The JobAgent is not run here 
#
#...............................................................................

function DIRACPilotInstall(){
	
	prepareForPilot
	
	#run the dirac-pilot script, the JobAgent won't necessarily match a job
	#FIXME: using LHCb-Certification here, and LHCb CS! 

	findRelease
 
	python dirac-pilot.py -S LHCb-Certification -r $projectVersion -C dips://lbvobox18.cern.ch:9135/Configuration/Server -N jenkins.cern.ch -Q jenkins-queue_not_important -n DIRAC.Jenkins.ch -M 1 --cert --certLocation=/home/dirac/certs/ $DEBUG
}

############################################ 
# Utilities


function getCertificate(){
	echo '[getCertificate]'
	# just gets a host certificate from a known location 
	
	mkdir -p $WORKSPACE/etc/grid-security/
	cp /root/hostcert.pem $WORKSPACE/etc/grid-security/
	cp /root/hostkey.pem $WORKSPACE/etc/grid-security/ 
	chmod 0600 $WORKSPACE/etc/grid-security/hostkey.pem

} 

function prepareForPilot(){
	
	#cert first (host certificate)
	#getCertificate (no need...)
	
	#get the necessary scripts
	wget --no-check-certificate -O dirac-install.py $DIRAC_INSTALL
	wget --no-check-certificate -O dirac-pilot.py $DIRAC_PILOT
	wget --no-check-certificate -O pilotTools.py $DIRAC_PILOT_TOOLS
	wget --no-check-certificate -O pilotCommands.py $DIRAC_PILOT_COMMANDS

}
