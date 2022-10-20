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
date="$( date -v-30d '+%Y-%m-%d')"

echo $date
## Defining functions
###Install Homebrew and jq
function installHomebrew {
#!/bin/sh
# AutoBrew - Install Homebrew with root
# Source: https://github.com/kennyb-222/AutoBrew/
# Author: Kenny Botelho
# Version: 1.2

# Set environment variables
HOME="$(mktemp -d)"
export HOME
export USER=root
export PATH="/usr/local/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
BREW_INSTALL_LOG=$(mktemp)

# Get current logged in user
TargetUser=$(echo "show State:/Users/ConsoleUser" | \
    scutil | awk '/Name :/ && ! /loginwindow/ { print $3 }')

# Check if parameter passed to use pre-defined user
if [ -n "$3" ]; then
    # Supporting running the script in Jamf with no specialization via Self Service
    TargetUser=$3
elif [ -n "$1" ]; then
    # Fallback case for the command line initiated method
    TargetUser=$1
fi

# Ensure TargetUser isn't empty
if [ -z "${TargetUser}" ]; then
    /bin/echo "'TargetUser' is empty. You must specify a user!"
    exit 1
fi

# Verify the TargetUser is valid
if /usr/bin/dscl . -read "/Users/${TargetUser}" 2>&1 >/dev/null; then
    /bin/echo "Validated ${TargetUser}"
else
    /bin/echo "Specified user \"${TargetUser}\" is invalid"
    exit 1
fi

# Install Homebrew | strip out all interactive prompts
/bin/bash -c "$(curl -fsSL \
    https://raw.githubusercontent.com/Homebrew/install/master/install.sh | \
    sed "s/abort \"Don't run this as root\!\"/\
    echo \"WARNING: Running as root...\"/" | \
    sed 's/  wait_for_user/  :/')" 2>&1 | tee "${BREW_INSTALL_LOG}"

# Reset Homebrew permissions for target user
brew_file_paths=$(sed '1,/==> This script will install:/d;/==> /,$d' \
    "${BREW_INSTALL_LOG}")
brew_dir_paths=$(sed '1,/==> The following new directories/d;/==> /,$d' \
    "${BREW_INSTALL_LOG}")
# Get the paths for the installed brew binary
brew_bin=$(echo "${brew_file_paths}" | grep "/bin/brew")
brew_bin_path=${brew_bin%/brew}
# shellcheck disable=SC2086
chown -R "${TargetUser}":admin ${brew_file_paths} ${brew_dir_paths}
chgrp admin ${brew_bin_path}/
chmod g+w ${brew_bin_path}

# Unset home/user environment variables
unset HOME
unset USER

# Finish up Homebrew install as target user
su - "${TargetUser}" -c "${brew_bin} update --force"

# Run cleanup before checking in with the doctor
su - "${TargetUser}" -c "${brew_bin} cleanup"

# Check for post-installation issues with "brew doctor"
doctor_cmds=$(su - "${TargetUser}" -i -c "${brew_bin} doctor 2>&1 | grep 'mkdir\|chown\|chmod\|echo\|&&'")

# Run "brew doctor" remediation commands
if [ -n "${doctor_cmds}" ]; then
    echo "\"brew doctor\" failed. Attempting to repair..."
    while IFS= read -r line; do
        echo "RUNNING: ${line}"
        if [[ "${line}" == *sudo* ]]; then
            # run command with variable substitution
            cmd_modified=$(su - "${TargetUser}" -c "echo ${line}")
            ${cmd_modified}
        else
            # Run cmd as TargetUser
            su - "${TargetUser}" -c "${line}"
        fi
    done <<< "${doctor_cmds}"
fi

# Check Homebrew install status, check with the doctor status to see if everything looks good
if su - "${TargetUser}" -i -c "${brew_bin} doctor"; then
    echo 'Homebrew Installation Complete! Your system is ready to brew.'
else
    echo 'AutoBrew Installation Failed'
    exit 1
fi
}

###Uninstall Homebrew
function installjq {

  if [[ $(uname -m) == 'arm64' ]]; then
    su "${UserName}" -c "/opt/homebrew/bin/brew install jq"
  else
    su "${UserName}" -c "/usr/local/bin/brew install jq"
  fi
}
###Get User id from Druva on m1 devices
function DruvaUserIDm1 {
  Emailid="${UserName}"
  DruvaUserid="$(curl --location --request GET "https://apis.druva.com/insync/usermanagement/v1/users?emailID=${Emailid}" \
  --header "Accept: application/json" \
  --header "Authorization: Bearer $BearerToken" |\
  /opt/homebrew/bin/jq -r '.users[].userID'
  )"
  echo "$DruvaUserid"
}
###Get devices associated with user  on m1 devices
function UserDevicesm1 {
#Pulls Device ID from most current Backup
DruvaDeviceid="$(curl --location --request GET "https://apis.druva.com/insync/endpoints/v1/backups?lastSuccessful=true&userID=$DruvaUserid&minBackupStartTime=${date}T00:00:00Z" \
  --header "Accept: application/json" \
  --header "Authorization: Bearer $BearerToken" |\
  /opt/homebrew/bin/jq -r 'first(.backups[].deviceID)')"
  echo "$DruvaDeviceid"

#Gets Device Name from Most current backup
LastBackupDeviceName="$(curl --location --request GET "https://apis.druva.com/insync/endpoints/v1/devices/$DruvaDeviceid" \
--header "Accept: application/json" \
--header "Authorization: Bearer $BearerToken" |\
/opt/homebrew/bin/jq -r '.deviceName'
)"
echo "$LastBackupDeviceName"
}
###Get User id from Druva for intel
function DruvaUserID_nonm1 {
  Emailid="${UserName}"
  DruvaUserid="$(curl --location --request GET "https://apis.druva.com/insync/usermanagement/v1/users?emailID=${Emailid}" \
  --header "Accept: application/json" \
  --header "Authorization: Bearer $BearerToken" |\
  /usr/local/bin/jq -r '.users[].userID'
  )"
  echo "$DruvaUserid"
}
###Get devices associated with user for intel
function UserDevices_nonm1 {
#Pulls Device ID from most current Backup
DruvaDeviceid="$(curl --location --request GET "https://apis.druva.com/insync/endpoints/v1/backups?lastSuccessful=true&userID=$DruvaUserid&minBackupStartTime=${30date}T00:00:00Z" \
  --header "Accept: application/json" \
  --header "Authorization: Bearer $BearerToken" |\
  /usr/local/bin/jq -r 'first(.backups[].deviceID)')"
  echo "$DruvaDeviceid"

#Gets Device Name from Most current backup
LastBackupDeviceName="$(curl --location --request GET "https://apis.druva.com/insync/endpoints/v1/devices/$DruvaDeviceid" \
--header "Accept: application/json" \
--header "Authorization: Bearer $BearerToken" |\
//usr/local/bin/jq -r '.deviceName'
)"
echo "$LastBackupDeviceName"
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
    \"restoreData\": \"ALL\"
}"
}

installHomebrew
installjq
if [[ $(uname -m) == 'arm64' ]]; then
  DruvaUserIDm1
  UserDevicesm1
else
  DruvaUserID_nonm1
  UserDevices_nonm1
fi

if [ $LastBackupDeviceName == "null"  ]; then
DruvaMapNoRestore
echo "Status: Computer is being backed up." >> "$DEP_NOTIFY_LOG"
else
  DruvaMapRestore
  echo "Status: Device is being restored." >> "$DEP_NOTIFY_LOG"
fi

exit 0
