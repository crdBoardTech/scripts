#!/bin/bash

###########################################################################################
############################################################################################
# Druva Device Mapping Automation
############################################################################################
#
#
# This script Automates the Device Mapping portion of Druva
#
# Purpose:
#     Restore User Data Upon completion of device deployment
#
#Created by: Gabriel Caba
###########################################################################################
###########################################
#  Variable Definition - Passed from JAMF
###########################################
apiUser=$4
apiPass=$5
JAMFURL=$6
Base64=$7
###########################################
#  Variable Definition - Staticly defined
###########################################
JAMF_BINARY="/usr/local/bin/jamf"
FDE_SETUP_BINARY="/usr/bin/fdesetup"
DEP_NOTIFY_APP="/Applications/Utilities/DEPNotify.app"
DEP_NOTIFY_LOG="/var/tmp/depnotify.log"
DEP_NOTIFY_DEBUG="/var/tmp/depnotifyDebug.log"
DruvaURL="https://apis.druva.com/insync/endpoints/v1/devicemappings"
BearerToken="$(curl -X POST -H "authorization: Basic $Base64" -d 'grant_type=client_credentials&scope=read' https://apis.druva.com/token| awk '{print $2}' |awk -F "," '{gsub("/", "-", $1); print $1}'| awk '{gsub(/"/, "", $1); print $1}')"
id="$(jamf recon | grep '<computer_id>' | xmllint --xpath xmllint --xpath '/computer_id/text()' -)"
EmailAddress="$( curl -su ${apiUser}:${apiPass} -X GET "${JAMFURL}/JSSResource/computers/id/$id/subset/UserAndLocation" -H "accept: application/xml"| xmllint --format - | awk -F">|<" '/<username/{print $3}')"
SerialNumber="$( curl -su ${apiUser}:${apiPass} -X GET "${JAMFURL}/JSSResource/computers/id/$id/subset/general" -H "accept: application/xml"| xmllint --format - | awk -F">|<" '/<serial_number/{print $3}')"
ComputerName="$( curl -su ${apiUser}:${apiPass} -X GET "${JAMFURL}/JSSResource/computers/id/$id/subset/general" -H "accept: application/xml"| xmllint --format - | awk -F">|<" '/<name/{print $3}'| awk 'NR==1{print $1,$2}')"
UserName="$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }')"

## Defining functions
###Install Homebrew and jq
function installHomebrew {
  installbrew=$(NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)")
  installjq=$(/opt/homebrew/bin/brew install jq)
}
###Uninstall Homebrew
function uninstallHomebrew {
  uninstallbrew=$(NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)")
}
###Get User id from Druva
function DruvaUserID {
  Emailid="${UserName}"%40nols.edu""
  DruvaUserid="$(curl --location --request GET "https://apis.druva.com/insync/usermanagement/v1/users?emailID=${Emailid}" \
  --header "Accept: application/json" \
  --header "Authorization: Bearer $BearerToken" |\
  /opt/homebrew/bin/jq -r '.users[].userID'
  )"
}
###Get devices associated with user
function UserDevices {
#Pulls Device ID from most current Backup
DruvaDeviceid="$(curl --location --request GET "https://apis.druva.com/insync/endpoints/v1/backups?lastSuccessful=true&userID=$DruvaUserid" \
  --header "Accept: application/json" \
  --header "Authorization: Bearer $BearerToken" |\
  /opt/homebrew/bin/jq -r 'first(.backups[].deviceID)')"

#Gets Device Name from Most current backup
LastBackupDeviceName="$(curl --location --request GET "https://apis.druva.com/insync/endpoints/v1/devices/$DruvaDeviceid" \
--header "Accept: application/json" \
--header "Authorization: Bearer $BearerToken" |\
/opt/homebrew/bin/jq -r '.deviceName'
)"
}
### Druva Device Map Api Call
####For Users with no available backups
function DruvaMapNoRestore {
curl -v --location --request POST "https://apis.druva.com/insync/endpoints/v1/devicemappings" \
--header "Accept: application/json" \
--header "Authorization: Bearer $BearerToken" \
--header "Content-Type: application/json" \
--data-raw "{
    \"emailID\": \"$EmailAddress\",
    \"userName\": \"$UserName\",
    \"deviceName\": \"$ComputerName\",
    \"deviceIdentifierType\": \"serial-number\",
    \"deviceIdentifier\": \"$SerialNumber\",

}"
}
### Druva Device Map Api Call initiates restore
####If an eligible backup is found device will be restored
function DruvaMapRestore {
curl -v --location --request POST "https://apis.druva.com/insync/endpoints/v1/devicemappings" \
--header "Accept: application/json" \
--header "Authorization: Bearer $BearerToken" \
--header "Content-Type: application/json" \
--data-raw "{
    \"emailID\": \"$EmailAddress\",
    \"userName\": \"$UserName\",
    \"deviceName\": \"$ComputerName\",
    \"deviceIdentifierType\": \"serial-number\",
    \"deviceIdentifier\": \"$SerialNumber\",
    \"oldDeviceName\": \"$LastBackupDeviceName\",
    \"restoreData\": \"DATA\"
}"
}

installHomebrew
if [ $LastBackupDeviceName == "null"  ]; then
DruvaMapNoRestore
echo "Status: Computer is being backed up." >> "$DEP_NOTIFY_LOG"
else
  DruvaMapRestorce
  echo "Status: Device is being restored." >> "$DEP_NOTIFY_LOG"
fi

exit 0
