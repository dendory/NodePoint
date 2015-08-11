#
# Use this script to query an Active Directory domain and add users into NodePoint.
# Make sure you disable AD integration first. You can then re-enable it to have users authenticate against AD.
#
# Configure the following values:
#
$DN = "OU=Users,DC=domain,DC=com"
$NodePointURL = "http://10.0.0.1/nodepoint"
$WriteKey = "c5BT44108cYxBRHOYLnykazABsjkkQP2"
$DefaultPassword = "123456"
#
# End configuration
#

Get-ADUser -filter * -searchbase $DN -Properties * | foreach { Invoke-WebRequest -Uri "$NodePointURL/?api=add_user&key=$WriteKey&user=$($_.samaccountname)&password=$DefaultPassword&email=$($_.mail)" | ConvertFrom-Json }
