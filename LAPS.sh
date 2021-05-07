#!/bin/zsh
####################################################################################################
#
#   MIT License
#
#   Copyright (c) 2019 Measures for Justice
#
#    Permission is hereby granted, free of charge, to any person obtaining a copy
#   of this software and associated documentation files (the "Software"), to deal
#   in the Software without restriction, including without limitation the rights
#   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#   copies of the Software, and to permit persons to whom the Software is
#   furnished to do so, subject to the following conditions:
#
#   The above copyright notice and this permission notice shall be included in all
#   copies or substantial portions of the Software.
#
#   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
#   SOFTWARE.
#
####################################################################################################
#
# HISTORY
#
#  - Original Git repo is here: https://github.com/NU-ITS/LAPSforMac
#    Last updated 2017
#  - Forked repo updated 2018 for Mojave: https://github.com/tbso/LAPSforMac
#    Last update Jan 2019
#  - 8/19 Creating zsh friendly copy for Catalina: https://github.com/scottgary/LAPSforMac
#    Version: 0.1
#
#   - This script will randomize the password of the specified user account and post the password to the LAPS Extention Attribute in Jamf.
#
####################################################################################################
#
# DEFINE VARIABLES & READ IN PARAMETERS
#
####################################################################################################

# HARDCODED VALUES SET HERE
apiUser="$4" # $4
apiPass="$5" # $5
resetUser="$6" # $6
apiURL="$7" #  $7
# hardcode log location
LogLocation="/private/var/log/$resetUser.log"
# hardcode full path to jamf binary.
jamf_binary="/usr/local/bin/jamf"

###################Create new Password#######################
newPass=$(env LC_CTYPE=C tr -dc "A-Za-z0-9#\$^&_+=" < /dev/urandom | head -c 16;echo | echo "Aq1*")

####################################################################################################
#
# SCRIPT CONTENTS - DO NOT MODIFY BELOW THIS LINE
#
####################################################################################################
extAttName="\"LAPS\""
extAttName2="\"oldLAPS\""
udid=$(/usr/sbin/system_profiler SPHardwareDataType | /usr/bin/awk '/Hardware UUID:/ { print $3 }')
oldPass=$(curl -s -u "$apiUser":"$apiPass" -H "Accept: application/xml" "$apiURL"/JSSResource/computers/udid/"$udid"/subset/extension_attributes | xpath -q -e "//extension_attribute[name=$extAttName]" 2>&1 | awk -F'<value>|</value>' '{print $2}' | tr -d '\n')
xmlString="<?xml version=\"1.0\" encoding=\"UTF-8\"?><computer><extension_attributes><extension_attribute><name>LAPS</name><value>$newPass</value></extension_attribute></extension_attributes></computer>"
xmlString2="<?xml version=\"1.0\" encoding=\"UTF-8\"?><computer><extension_attributes><extension_attribute><name>oldLAPS</name><value>$oldPass</value></extension_attribute></extension_attributes></computer>"

# Logging Function for reporting actions
ScriptLogging(){

DATE=$(date +%Y-%m-%d\ %H:%M:%S)
LOG="$LogLocation"

echo "$DATE" " $1" >> $LOG
}

ScriptLogging "======== Starting LAPS Update ========"
ScriptLogging "Checking parameters."

# Verify parameters are present
if [ "$apiUser" = "" ];then
  ScriptLogging "Error:  The parameter 'API Username' is blank.  Please specify a user."
  echo "Error:  The parameter 'API Username' is blank.  Please specify a user."
  ScriptLogging "======== Aborting LAPS Update ========"
  exit 1
fi

if [ "$apiPass" = "" ];then
  ScriptLogging "Error:  The parameter 'API Password' is blank.  Please specify a password."
  echo "Error:  The parameter 'API Password' is blank.  Please specify a password."
  ScriptLogging "======== Aborting LAPS Update ========"
  exit 1
fi

if [ "$resetUser" = "" ];then
  ScriptLogging "Error:  The parameter 'User to Reset' is blank.  Please specify a user to reset."
  echo "Error:  The parameter 'User to Reset' is blank.  Please specify a user to reset."
  ScriptLogging "======== Aborting LAPS Update ========"
  exit 1
fi

# Verify resetUser is a local user on the computer
checkUser=$(dscl . list /Users | grep "$resetUser")

if [[ -z  "$checkUser" ]]; then
  echo "Error: $checkUser is not a local user on the Computer!"
  ScriptLogging "======== Aborting LAPS Update ========"
  exit 1
else
  echo "$resetUser is a local user on the Computer"
fi

ScriptLogging "Parameters Verified."

# Verify the current User Password in Jamf Pro LAPS
CheckOldPassword (){
ScriptLogging "Verifying password stored in LAPS."
if [ -z "$oldPass" ]; then
  ScriptLogging "No Password is stored in LAPS."
  echo "No Password is stored in LAPS."
  ScriptLogging "======== Aborting LAPS Update ========"
  echo "======== Aborting LAPS Update ========"
  exit 1
else
  ScriptLogging "A Password was found in LAPS."
  echo "A Password was found in LAPS."
fi

passwdA=$(dscl /Local/Default -authonly "$resetUser" "$oldPass")

if [ "$passwdA" = "" ];then
  ScriptLogging "Password stored in LAPS is correct for $resetUser."
  echo "Password stored in LAPS is correct for $resetUser."
else
  ScriptLogging "Error: Password stored in LAPS is not valid for $resetUser."
  echo "Error: Password stored in LAPS is not valid for $resetUser."
  ScriptLogging "======== Aborting LAPS Update ========"
  echo "======== Aborting LAPS Update ========"
  exit 1
fi
}

# Store the old password and verify that it's stored before attempting to reset it
StoreOldPass (){
ScriptLogging "Recording previous password for $resetUser into LAPS."
/usr/bin/curl -s -u ${apiUser}:${apiPass} -X PUT -H "Content-Type: text/xml" -d "${xmlString2}" "${apiURL}/JSSResource/computers/udid/$udid"

sleep 1

TestPass=$(curl -s -f -u $apiUser:$apiPass -H "Accept: application/xml" $apiURL/JSSResource/computers/udid/$udid/subset/extension_attributes | xpath "//extension_attribute[name=$extAttName2]" 2>&1 | awk -F'<value>|</value>' '{print $2}' | tr -d '\n')

ScriptLogging "Verifying the current password has been backed up"
if [ "$TestPass" = "$oldPass" ];then
  ScriptLogging "The old Password has been stored"
  echo "The old Password has been stored"
else
  ScriptLogging "Error: The old password has not been backud up"
  echo "Error: The old password has not been backud up"
  ScriptLogging "======== Aborting LAPS Update ========"
  echo "======== Aborting LAPS Update ========"
  exit 1
fi
}

# Update the User Password
RunLAPS (){
ScriptLogging "Running LAPS..."
if [ "$oldPass" = "" ];then
  ScriptLogging "Current password not available, aborting LAPS script."
  echo "Current password not available, aborting LAPS script."
  exit 1
else
  ScriptLogging "Updating password for $resetUser."
  echo "Updating password for $resetUser."
  sysadminctl -adminUser $resetUser -adminPassword $oldPass -resetPasswordFor $resetUser -newPassword $newPass
fi
}

# Verify the new User Password
CheckNewPassword (){
ScriptLogging "Verifying new password for $resetUser."
passwdB=$(dscl /Local/Default -authonly $resetUser $newPass)

if [ -z "$passwdB" ]; then
  ScriptLogging "New password for $resetUser is verified."
  echo "New password for $resetUser is verified."
else
  ScriptLogging "Error: Password reset for $resetUser was not successful!"
  echo "Error: Password reset for $resetUser was not successful!"
  ScriptLogging "======== Aborting LAPS Update ========"
  exit 1
fi
}

# Update the LAPS Extention Attribute
UpdateAPI (){
ScriptLogging "Recording new password for $resetUser into LAPS."
echo "Recording new password for $resetUser into LAPS."

/usr/bin/curl -s -u ${apiUser}:${apiPass} -X PUT -H "Content-Type: text/xml" -d "${xmlString}" "${apiURL}/JSSResource/computers/udid/$udid"

sleep 1

LAPSpass=$(curl -s -f -u $apiUser:$apiPass -H "Accept: application/xml" $apiURL/JSSResource/computers/udid/$udid/subset/extension_attributes | xpath "//extension_attribute[name=$extAttName]" 2>&1 | awk -F'<value>|</value>' '{print $2}' | tr -d '\n')

ScriptLogging "Verifying LAPS password for $resetUser."
echo "Verifying LAPS password for $resetUser."

if [ $LAPSpass = $newPass ];then
  ScriptLogging "LAPS password for $resetUser is verified."
  echo "LAPS password for $resetUser is verified."
else
  ScriptLogging "Error: LAPS password for $resetUser is not correct!"
  ScriptLogging "======== Aborting LAPS Update ========"
  echo "Error: LAPS password for $resetUser is not correct!"
  exit 1
fi
}

CheckOldPassword
StoreOldPass
UpdateAPI
RunLAPS
CheckNewPassword

ScriptLogging "======== LAPS Update Finished ========"
echo "LAPS Update Finished; Running Recon"
$jamf_binary recon

exit 0
