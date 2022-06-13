#!/bin/bash

###########################################################################################
############################################################################################
# User Force Logout
############################################################################################
#
#
# This script is meant to log out current user after instlling JAmf connect
#
# Purpose:
#     User Sign out to nstall JAMF connect
###########################################################################################

#Defining Functions and Variables
loggedInUserID=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/kCGSSessionUserIDKey :/ { print $3 }')

function Logout {
  osascript\
  -e 'try'\
  -e 'ignoring application responses'\
  -e 'tell application "/System/Library/CoreServices/loginwindow.app" to «event aevtrlgo»'\
  -e 'end ignoring'\
  -e 'end try'
    }


function Prompt {
  Result=$(/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper \
  -windowType utility \
  -lockHUD \
  -title "JAMF Connect Upgrade" \
  -heading "ALERT: You will be signed out!" \
  -description "Please select an option below, and please take the time to save all your documents." \
  -icon "$4" \
  -iconSize 256 \
  -button1 "ok" \
  -defaultButton 1 \
  -showDelayOptions "0, 150, 300")
                  }

function Confirmation {
  /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper \
          -windowType utility \
          -lockHUD \
          -title "JAMF Connect Upgrade" \
          -heading "ALERT: Your upgrade is about to start!" \
          -description "You will be signed out soon, please save your documents." \
          -icon "$4"  \
          -iconSize 256 \
          -countdown \
          -timeout ${Result} \
          -alignCountdown right
}

function Authchanger {
  sudo authchanger -reset -JamfConnect
}
# Displays a dialog to the end user with a five minute countdown. If the countdown reaches 0:00 or the user clicks the button, the dialog disappears allowing the remainder of the workflow to proceed.

Prompt

if [ $Result == 1 ]; then
# Logging out now
Authchanger
Confirmation
Logout

elif [ $Result == 1501 ]; then
# Delay 2:30 Minutes
Result=150
Authchanger
Confirmation
Logout

elif [ $Result == 3001 ]; then
# Delay 5 Minutes
Result=300
Authchanger
Confirmation
Logout
fi
