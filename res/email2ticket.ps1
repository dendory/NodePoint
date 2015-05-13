# This script will connect to an IMAP server, download new messages, then file tickets into a NodePoint Ticket System.
# Uses the ImapX library from https://imapx.codeplex.com/ provided under the Apache License
# You can use the Task Scheduler to run this script every X minutes.
#
# Begin configuration
#
# Your email server hostname
$IMAPServer = "mail.domain.com"
# Your email server port
$IMAPPort = 143
# Use SSL to connect?
$IMAPSSL = $false
# Your email account username
$IMAPUsername = "support@domain.com"
# Your email account password
$IMAPPassword = "Test1234"
# Your NodePoint server URL
$NodePointURL = "http://10.0.0.1/nodepoint"
# Your API WRITE key
$NodePointAPIKEY = "XXXXXXXXXXXXXXXXXXXXXXXXXX"
# The product ID on which to file ticket
$NodePointProduct = "1"
# The release name in that product
$NodePointRelease = "1.0"
# Impersonate user? The proper setting must be set if you wish tickets to be filed as the users that sent them, instead of 'api'
$NodePointImp = $false
#
# End configuration
#

Import-Module ".\imapx.dll"   # The file imapx.dll must be in the same folder
$client = New-Object ImapX.ImapClient    # Create the client object
$client.Behavior.MessageFetchMode = "Full"    # Fetch the full body of messages
$client.Host = $IMAPServer
$client.Port = $IMAPPort
$client.UseSsl = $IMAPSSL
$client.Connect() | Out-Null     # Connect to the IMAP server
$client.Login($IMAPUsername, $IMAPPassword) | Out-Null     # Login to the IMAP server
$messages = $client.Folders.Inbox.Search("UNSEEN", $client.Behavior.MessageFetchMode, 1000)     # Search for unread messages with a max of 1000
foreach($m in $messages)    # Loop through messages
{
    $ticketTitle = "$($m.Subject)"    # Build the ticket's title
    $ticketDescription = "Ticket from: $($m.From.DisplayName) ($($m.From.Address))`n`n$($m.body.Text)"      # Build the ticket's description
    $ticketFrom = "$($m.From.DisplayName)" -replace " ",""   # Set the user name for impersonation, or 'api' if no display name
    if($ticketFrom -eq "") { $ticketFrom = "api" }
    if($NodePointImp) { $a = Invoke-WebRequest -Uri "$NodePointUrl/?api=add_ticket&key=$NodePointAPIKEY&product_id=$NodePointProduct&release_id=$NodePointRelease&title=$([uri]::EscapeDataString($ticketTitle))&description=$([uri]::EscapeDataString($ticketDescription))&from_user=$([uri]::EscapeDataString($ticketFrom))" }    # File the ticket with impersonation
    else { $a = Invoke-WebRequest -Uri "$NodePointUrl/?api=add_ticket&key=$NodePointAPIKEY&product_id=$NodePointProduct&release_id=$NodePointRelease&title=$([uri]::EscapeDataString($ticketTitle))&description=$([uri]::EscapeDataString($ticketDescription))" }    # File the ticket without
    $a.Content    # Display the result
    $m.SEEN = $true    # Set message as read
}
