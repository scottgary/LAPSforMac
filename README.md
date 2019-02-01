# LAPSforMac -- updated compatibility for Mojave and High Sierra

Huge, **huge** kudos to Phil Redfern and the University of Nebraska for this script. I simply updated the LAPS script to resolve some quirks with the Jamf binary in High Sierra, resulting in odd behavior regarding secureToken and FileVault enablement. I'm using this script to update a local admin account through a Jamf policy, however you can repurpose this script to be used outside of Jamf.


## `dscl`, secureToken, and FileVault

* The original LAPS script uses `$jamf_binary` to reset the user password, which in turn utilizes `dscl`
* `dscl` technically performs a successful password reset, however it exhibits the following behavior in macOS 10.13.6 when a Jamf policy executes the LAPS script on an AD-bound machine:
  
### Scenario 1
  
* A local admin account with secureToken is currently logged in. The local admin logs out.
* AD-user logs in
* A secureToken dialog window appears to request an admin's credentials to enable secureToken for the AD-user
* secureToken is successfully enabled for the AD-user
* Run `sysadminctl -secureTokenStatus ADUserHere` to confirm secureToken is ENABLED
* A Jamf policy silently changes the local admin user's password in the background using the LAPS script
* The AD-user logs out to trigger a deferred FileVault enablement, but an error appears stating FileVault could not be enabled
* Reboot and log in as the local admin user using the new LAPS password
* Run `sysadminctl -secureTokenStatus LocalAdminUserHere` to confirm secureToken is ENABLED for the local admin
* Run `sysadminctl -secureTokenStatus ADUserHere` and discover secureToken is DISABLED for the AD-user, despite "successfully" gaining a secureToken during the initial AD-user login
* Attempt to enable FileVault via System Preferences or `fdesetup` while logged in as the local admin, receive same error
* Log out of local admin account, deferred FileVault enablement dialog window appears, receive same error
* So even though `sysadminctl` says the local admin has a secureToken, `dscl` somehow strips this attribute from both the local admin & AD-user when the Jamf policy ran the LAPS script.

### Scenario 2

* Before the local admin account is able to sign in for the first time (created via PreStage Enrollment, Setup Assistant, or pkg/script), a Jamf policy silently changes the local admin password in the background using the LAPS script
* The local admin signs in using the new LAPS password
* Run `sysadminctl -secureTokenStatus LocalAdminUserHere` to find that secureToken is DISABLED
* It appears that because `dscl` changed the user password before the first login, it somehow strips the secureToken attribute from the first local admin user account signing in
* If the sole admin account on the machine has no secureToken, there's no way to create an additional user with secureToken, or enable FileVault


## Resolution: use `sysadminctl`

Replace `$jamf_binary resetPassword -username $resetUser -password $newPass`

with

`sysadminctl -adminUser $resetUser -adminPassword $oldPass -resetPasswordFor $resetUser -newPassword $newPass`

In addition: because `sysadminctl -resetPasswordFor` will force the creation of a new Keychain, you can comment out/ignore `$jamf_binary resetPassword -updateLoginKeychain -username $resetUser -oldPassword $oldPass -password $newPass`

## Mojave and Jamf Extended Attributes

In macOS 10.14 and Jamf Pro 10.7 (and later) the policy will fail unless you store the previous LAPS password value in an additional Extended Attribute. This prevents issues verifying the new password is correct, and is stored in Jamf. The script has been updated to create this new EA using the Jamf API. 

## Sync a mismatched FileVault password in Mojave

* In Mojave, if a mobile Active Directory user password is changed off of the Mac (Active Directory, Okta, a network-bound Windows PC, etc) the FileVault password will never sync with the new password.
* Some users report that the Keychain password has diffculy syncing, or odd behavior where a user's password alternates between the old/cached password and the new/network password based on whether the user is connected to the corporate network
* A simple restart does not resolve the issue
* If you're using the LAPS script in a Jamf extended attribute, use this new script to grab the LAPS value to assist with syncing the new network password with FileVault
