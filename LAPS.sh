#!/bin/sh
####################################################################################################
#
#   MIT License
#
#   Copyright (c) 2016 University of Nebraska Lincoln
#
#   Permission is hereby granted, free of charge, to any person obtaining a copy
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
#   Version: 1.6
#
#   - 04/29/2016 Created by Phil Redfern
#   - 05/01/2016 Updated by Phil Redfern, added upload verification and local Logging.
#   - 05/02/2016 Updated by Phil Redfern and John Ross, added keychain update and fixed a bug where no stored LAPS password would cause the process to hang.
#   - 05/06/2016 Updated by Phil Redfern, improved local logging and increased random passcode length.
#   - 05/11/2016 Updated by Phil Redfern, removed ambiguous characters from the password generator.
#   - 08/29/2018 Updated by Stephen Short, replaced $jamf_binary with sysadminctl for updating the user password. This is to address issues with secureToken and FileVault enablement in 10.13.6 and later. Commented out -updateLoginKeychain as sysadminctl -resetPasswordFor will always create a new Keychain for the user
#	- 10/19/2018 Updated by Kelly Dickson, created an additional extension attribute to store the old/previous LAPS password value to assist with sysadminctl. This addresses a password sync issue in Jamf Pro 10.7 and Mojave
#
#   - This script will randomize the password of the specified user account and post the password to the LAPS Extention Attribute in Jamf Pro.
#
####################################################################################################
#
# DEFINE VARIABLES & READ IN PARAMETERS
#
####################################################################################################
 
# HARDCODED VALUES SET HERE
apiUser="EnterAPIUserHere"
apiPass="EnterAPIPasswordHere"
resetUser="EnterResetAdminUserHere"
 
# CHECK TO SEE IF A VALUE WAS PASSED IN PARAMETER 4 AND, IF SO, ASSIGN TO "apiUser"
if [ "$4" != "" ] && [ "$apiUser" == "" ];then
apiUser=$4
fi
 
# CHECK TO SEE IF A VALUE WAS PASSED IN PARAMETER 5 AND, IF SO, ASSIGN TO "apiPass"
if [ "$5" != "" ] && [ "$apiPass" == "" ];then
apiPass=$5
fi
 
# CHECK TO SEE IF A VALUE WAS PASSED IN PARAMETER 6 AND, IF SO, ASSIGN TO "resetUser"
if [ "$6" != "" ] && [ "$resetUser" == "" ];then
resetUser=$6
fi
 
apiURL="EnterapiURLHere"
LogLocation="/Library/Logs/Casper_LAPS.log"
 
newPass=$(env LC_CTYPE=C tr -dc "A-Za-z0-9#$^&_+=" < /dev/urandom | head -c 12;echo)
#newPass=$(openssl rand -base64 10 | tr -d OoIi1lLS | head -c12;echo)
#
####################################################################################################
#
# SCRIPT CONTENTS - DO NOT MODIFY BELOW THIS LINE
#
####################################################################################################
extAttName="\"LAPS\""
extAttName2="\"oldLAPS\""
udid=$(/usr/sbin/system_profiler SPHardwareDataType | /usr/bin/awk '/Hardware UUID:/ { print $3 }')
oldPass=$(curl -s -f -u $apiUser:$apiPass -H "Accept: application/xml" $apiURL/JSSResource/computers/udid/$udid/subset/extension_attributes | xpath "//extension_attribute[name=$extAttName]" 2>&1 | awk -F'<value>|</value>' '{print $2}')
xmlString="<?xml version=\"1.0\" encoding=\"UTF-8\"?><computer><extension_attributes><extension_attribute><name>LAPS</name><value>$newPass</value></extension_attribute></extension_attributes></computer>"
xmlString2="<?xml version=\"1.0\" encoding=\"UTF-8\"?><computer><extension_attributes><extension_attribute><name>oldLAPS</name><value>$oldPass</value></extension_attribute></extension_attributes></computer>"
 
# Logging Function for reporting actions
ScriptLogging(){
 
DATE=`date +%Y-%m-%d\ %H:%M:%S`
LOG="$LogLocation"
 
echo "$DATE" " $1" >> $LOG
}
 
ScriptLogging "======== Starting LAPS Update ========"
ScriptLogging "Checking parameters."
 
# Verify parameters are present
if [ "$apiUser" == "" ];then
    ScriptLogging "Error:  The parameter 'API Username' is blank.  Please specify a user."
    echo "Error:  The parameter 'API Username' is blank.  Please specify a user."
    ScriptLogging "======== Aborting LAPS Update ========"
    exit 1
fi
 
if [ "$apiPass" == "" ];then
    ScriptLogging "Error:  The parameter 'API Password' is blank.  Please specify a password."
    echo "Error:  The parameter 'API Password' is blank.  Please specify a password."
    ScriptLogging "======== Aborting LAPS Update ========"
    exit 1
fi
 
if [ "$resetUser" == "" ];then
    ScriptLogging "Error:  The parameter 'User to Reset' is blank.  Please specify a user to reset."
    echo "Error:  The parameter 'User to Reset' is blank.  Please specify a user to reset."
    ScriptLogging "======== Aborting LAPS Update ========"
    exit 1
fi
 
# Verify resetUser is a local user on the computer
checkUser=`dseditgroup -o checkmember -m $resetUser localaccounts | awk '{ print $1 }'`
 
if [[ "$checkUser" = "yes" ]];then
    echo "$resetUser is a local user on the Computer"
else
    echo "Error: $checkUser is not a local user on the Computer!"
    ScriptLogging "======== Aborting LAPS Update ========"
    exit 1
fi
 
ScriptLogging "Parameters Verified."
 
# Identify the location of the jamf binary for the jamf_binary variable.
CheckBinary (){
# Identify location of jamf binary.
jamf_binary=`/usr/bin/which jamf`
 
if [[ "$jamf_binary" == "" ]] && [[ -e "/usr/sbin/jamf" ]] && [[ ! -e "/usr/local/bin/jamf" ]]; then
jamf_binary="/usr/sbin/jamf"
elif [[ "$jamf_binary" == "" ]] && [[ ! -e "/usr/sbin/jamf" ]] && [[ -e "/usr/local/bin/jamf" ]]; then
jamf_binary="/usr/local/bin/jamf"
elif [[ "$jamf_binary" == "" ]] && [[ -e "/usr/sbin/jamf" ]] && [[ -e "/usr/local/bin/jamf" ]]; then
jamf_binary="/usr/local/bin/jamf"
fi
 
ScriptLogging "JAMF Binary is $jamf_binary"
echo "JAMF Binary is $jamf_binary"
}
 
# Verify the current User Password in Jamf Pro LAPS
CheckOldPassword (){
ScriptLogging "Verifying password stored in LAPS."
 
if [ "$oldPass" == "" ];then
    ScriptLogging "No Password is stored in LAPS."
    echo "No Password is stored in LAPS."
    ScriptLogging "======== Aborting LAPS Update ========"
    echo "======== Aborting LAPS Update ========"
    exit 1
else
    ScriptLogging "A Password was found in LAPS."
    echo "A Password was found in LAPS."
fi
 
passwdA=`dscl /Local/Default -authonly $resetUser $oldPass`
 
if [ "$passwdA" == "" ];then
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
 
TestPass=$(curl -s -f -u $apiUser:$apiPass -H "Accept: application/xml" $apiURL/JSSResource/computers/udid/$udid/subset/extension_attributes | xpath "//extension_attribute[name=$extAttName2]" 2>&1 | awk -F'<value>|</value>' '{print $2}')
 
ScriptLogging "Verifying the current password has been backed up"
if [ "$TestPass" == "$oldPass" ];then
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
if [ "$oldPass" == "" ];then
    ScriptLogging "Current password not available, aborting LAPS script."
    echo "Current password not available, aborting LAPS script."
    #-Broken in High Sierra with SecureToken-# $jamf_binary resetPassword -username $resetUser -password $newPass
    exit 1
else
    ScriptLogging "Updating password for $resetUser."
    echo "Updating password for $resetUser."
    #-Broken in High Sierra with SecureToken-# $jamf_binary resetPassword -updateLoginKeychain -username $resetUser -oldPassword $oldPass -password $newPass
    sysadminctl -adminUser $resetUser -adminPassword $oldPass -resetPasswordFor $resetUser -newPassword $newPass
fi
}
 
# Verify the new User Password
CheckNewPassword (){
ScriptLogging "Verifying new password for $resetUser."
passwdB=`dscl /Local/Default -authonly $resetUser $newPass`
 
if [ "$passwdB" == "" ];then
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
 
LAPSpass=$(curl -s -f -u $apiUser:$apiPass -H "Accept: application/xml" $apiURL/JSSResource/computers/udid/$udid/subset/extension_attributes | xpath "//extension_attribute[name=$extAttName]" 2>&1 | awk -F'<value>|</value>' '{print $2}')
 
ScriptLogging "Verifying LAPS password for $resetUser."
echo "Verifying LAPS password for $resetUser."
 
if [ $LAPSpass == $newPass ];then
    ScriptLogging "LAPS password for $resetUser is verified."
    echo "LAPS password for $resetUser is verified."
else
    ScriptLogging "Error: LAPS password for $resetUser is not correct!"
    ScriptLogging "======== Aborting LAPS Update ========"
    echo "Error: LAPS password for $resetUser is not correct!"
    exit 1
fi
}
 
CheckBinary
CheckOldPassword
StoreOldPass
UpdateAPI
RunLAPS
CheckNewPassword
 
 
ScriptLogging "======== LAPS Update Finished ========"
echo "LAPS Update Finished."
 
exit 0
