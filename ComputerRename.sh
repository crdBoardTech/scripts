#!/bin/bash

#######################################
#
#Purpose: Rename the device to the UserName plus device type
#
#Created by: Gabriel Caba
#
########################################
###########################################
#   Variables passed from Policy Parameters
###########################################
apiUser=$4
apiPass=$5
JAMFURL=$6
###########################################
#   JAMF and DEP
###########################################
JAMF_BINARY="/usr/local/bin/jamf"
FDE_SETUP_BINARY="/usr/bin/fdesetup"
DEP_NOTIFY_APP="/Applications/Utilities/DEPNotify.app"
DEP_NOTIFY_LOG="/var/tmp/depnotify.log"
DEP_NOTIFY_DEBUG="/var/tmp/depnotifyDebug.log"

###########################################
#   Script Variables
####"#######################################
id=$(sudo jamf recon | grep '<computer_id>' | xmllint --xpath xmllint --xpath '/computer_id/text()' -)
model="$( curl -su ${apiUser}:${apiPass} -X GET "$JAMFURL/JSSResource/computers/id/$id/subset/hardware" -H "accept: application/xml" | xmllint --format - | awk -F">|<" '/<model/{print $3}' | awk 'NR==1{print $1}')"
currentuser="$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }')"
ComputerName="${currentuser} ${model}"


#Updating DEP Notify Log
echo "Status: Renaming The Computer" >> "$DEP_NOTIFY_LOG"

#Renaming Computer
/usr/sbin/scutil --set ComputerName "${ComputerName}"
/usr/sbin/scutil --set LocalHostName "${ComputerName}"
/usr/sbin/scutil --set HostName "${ComputerName}"
diskutil rename / "${computerName}"

#Updating JAMF record
jamf recon
echo "Status: Computer has been renamed" >> "$DEP_NOTIFY_LOG"
exit 0
