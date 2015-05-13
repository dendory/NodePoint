# NodePoint Import CSV Script
#
param([string]$CSVFile = "", [string]$APIKey = "" , [string]$URL = "", [switch]$Preview = $false)

if($CSVFile -eq "" -or $APIKey -eq "" -or $URL -eq "")
{
    Write-Host "This script can import tickets from a CSV file to a NodePoint instance."
    Write-Host "Syntax: import_csv.ps1 -CSVFile <file.csv> -APIKey <write key> -URL <NodePoint URL> [-Preview]"
    Write-Host
    Write-Host "The CSV file must have the following headers: product_id,release_id,title,description,custom"
    exit(0)
}
$data = Import-Csv $CSVFile

if($Preview -eq $true)
{
    $data | Format-Table -AutoSize
    exit(0)
}

$null = [System.Reflection.Assembly]::LoadWithPartialName("System.Web.Extensions")
$ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer

foreach($d in $data)
{
    $product = $d.product_id
    $release = $d.release_id
    $custom = $d.custom
    $description = $d.description
    $title = $d.title
    $call = "$URL/?api=add_ticket&key=$APIKEY&product_id=$product&release_id=$release&title=$title&description=$description&custom=$custom"
    Write-Host
    Write-Host "Adding ticket: $title"
    $result = Invoke-WebRequest $call
    $a = $ser.DeserializeObject($result.Content)
    $b = $a.message
    $c = $a.status
    Write-Host "Result: $b [$c]"
}