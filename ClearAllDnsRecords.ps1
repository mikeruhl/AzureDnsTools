param (
    [string]$SubscriptionId,
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    [Parameter(Mandatory = $true)]
    [string]$DnsZoneName,
    [string]$RecordTypes
)
# Login to Azure and select subscription
Write-Host "Checking current Azure log in"
$context = Get-AzSubscription -erroraction 'silentlycontinue'
if(!$context){
    Write-Output "Logging in"
    $context = Connect-AzAccount
}else{
    Write-Output "Continuing with existing login"
}

if ($SubscriptionId) {
    # Let the user select the subscription
    Write-Output "Selecting subscription '$SubscriptionId'";
    $context = Select-AzSubscription -SubscriptionId $SubscriptionId;
}

if($null -eq $context){
    Write-Output "Could not connect to Azure, exiting"
    exit
}

Write-Output "Getting resource information from Azure DNS Zones for $($DnsZoneName)"
$dnsZone = Get-AzDnsZone -ResourceGroupName $ResourceGroupName -Name $DnsZoneName -erroraction 'silentlycontinue'
if ($null -eq $dnsZone) {
    Write-Output "The Dns Zone could not be retrieved, please check your settings and try again."
    exit
}

Write-Output "Getting record information from Azure"
$existingRecords = Get-AzDnsRecordSet -ZoneName $dnsZone.Name -ResourceGroupName $ResourceGroupName -erroraction 'silentlycontinue'
Write-Output "Retrieved $($existingRecords.Length) existing DNS Zone Records"

$filteredZones = @()

if($RecordTypes){
    $splits = $RecordTypes.Split(",")
    $filteredZones = $existingRecords.where({$splits.Contains($_.RecordType.ToString()) -and $_.RecordType -ne "SOA" -and $_.RecordType -ne "NS"})
} else{
    $filteredZones = $existingRecords.where({$_.RecordType -ne "SOA" -and $_.RecordType -ne "NS"})
}

Write-Output "Removing $($filteredZones.Count) records that match the type filter"

foreach ($zone in $filteredZones) {
    Write-Output "Clearing entry: {$($zone.Name), $($zone.RecordType), $($zone.Records[0].ToString())}"
    Remove-AzDnsRecordSet -ZoneName $DnsZoneName -ResourceGroupName $ResourceGroupName -Name $zone.Name -RecordType $zone.RecordType 
}

Write-Host "Done Clearing Entries"