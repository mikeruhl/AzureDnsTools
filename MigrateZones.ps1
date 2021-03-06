param (
    [Parameter(Mandatory = $true)]
    [string]$FileName,
    #The subscription id where the domain will be transfered.
    [string]$SubscriptionId,
    [string]$OverrideDomainName,
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    [int32]$DefaultTtl = 3600,
    [string]$IpFilterSource,
    [switch]$Force
)
# Login to Azure and select subscription
Write-Host "Checking current Azure log in"
$context = Get-AzSubscription -erroraction 'silentlycontinue'
if (!$context) {
    Write-Output "Logging in"
    $context = Connect-AzAccount
}
else {
    Write-Output "Continuing with existing login"
}


if ($SubscriptionId) {
    # Let the user select the subscription
    Write-Output "Selecting subscription '$SubscriptionId'";
    $context = Select-AzSubscription -SubscriptionId $SubscriptionId;
}

if ($null -eq $context) {
    Write-Output "Could not connect to Azure, exiting"
    exit
}

if ($OverrideDomainName) {
    $domain = $OverrideDomainName
}
else {
    Write-Output "Getting domain from filename"
    $domain = Split-Path $FileName -Leaf
    $domain = $domain.Substring(0, $domain.Length - 4);
    if (!$Force) {
        $confirmation = Read-Host "Is the domain $($domain)? [y/n]"
        while ($confirmation -ne "y") {
            if ($confirmation -eq 'n') {
                Write-Host "Fix the file name and rerun script"
                exit
            }
            $confirmation = Read-Host "Is the domain $($domain)? [y/n]"
        }
    }
}
Write-Output "Using $($domain) as the domain"

Write-Output "Getting resource information from Azure DNS Zones for $($domain)"
$dnsZone = Get-AzDnsZone -ResourceGroupName $ResourceGroupName -Name $domain -erroraction 'silentlycontinue'
if ($null -eq $dnsZone) {
    if (!$Force) {
        $confirmation = Read-Host "The DNS Zone was not found in the resource group $($ResourceGroupName).  Do you want to create the DNS Zone $($domain)? [y/n]"
        while ($confirmation -ne "y") {
            if ($confirmation -eq 'n') {
                Write-Host "You will need to create this dns zone manually and rerun the script"
                exit
            }
            $confirmation = Read-Host "The DNS Zone was not found in the resource group $($ResourceGroupName).  Do you want to create the DNS Zone $($domain)? [y/n]"
        }
    }

    $dnsZone = New-AzDnsZone -ResourceGroupName $ResourceGroupName -Name $domain -erroraction 'silentlycontinue'
    if ($null -eq $dnsZone) {
        Write-Error "The DNS Zone was required to be created and could not be.  This could be a permission issue or an issue with the script.  Please create the resource manually and try again"
        exit
    }
}

Write-Output "Getting record information from Azure"
$existingRecords = Get-AzDnsRecordSet -ZoneName $dnsZone.Name -ResourceGroupName $ResourceGroupName -erroraction 'silentlycontinue'
Write-Output "Retrieved $($existingRecords.Length) existing DNS Zone Records"


Write-Output "Accessing File $($FileName)"

$dnsZones = Import-Csv $FileName;
Write-Output "Found $($dnsZones.Length) records in file";

$useNames = ($null -ne $dnsZones.name -and
    $null -ne $dnsZones.ttl -and
    $null -ne $dnsZones.type -and
    $null -ne $dnsZones.value)
if ($useNames) {
    Write-Output "Found header names, will use those."
}
else {
    Write-Output "Did not find header names: 'name', 'type', 'value', 'ttl'. These need to be specified as a header in the csv file."

    exit
}

# prune suffix to compare. 
foreach ($zone in $dnsZones.where( {$_.type -ne "SOA" -and $_.type -ne "NS"})) {
    if ($zone.name.endswith($domain)) {
        $zone.name = $zone.name.Substring(0, $zone.name.length - $domain.length)
    }

    if ($zone.name.endswith(".")) {
        $zone.name = $zone.name.Substring(0, $zone.name.length - 1)
    }

    if ($zone.name.length -eq 0) {
        $zone.name = "@"
    }
}

foreach ($zone in $dnsZones.where( {$_.type -ne "SOA" -and $_.type -ne "NS"})) {
    $prettyPrint = "{$($zone.name), $($zone.type), $($zone.value)}"

    #check if it's a Peer 1 IP and skip
    if($null -ne $IpFilterSource) {
    if($zone.value.startswith($IpFilterSource)){
        Write-Warning "Filtered Server: $($prettyPrint), skipping"
        continue
    }}

    #ensure flip-flopping of @/* is correct for Azure.
    if ($zone.name -eq "@" -and $zone.type -eq "CNAME") {
        Write-Warning "This entry is invalid, CNAMEs can't use @ prefix: $($prettyPrint)"
        continue;
    }

    #check if empty prefix (some entries are blank)
    if ([string]::IsNullOrEmpty($zone.name)) {
        Write-Warning "This Entry is missing a prefix, one should be provided: $($prettyPrint)"
        continue
    }
    
    #Set Default TTL
    $ttl = $zone.ttl;
    if ([string]::IsNullOrEmpty($ttl)) {
        $ttl = $DefaultTtl
    }

    #Get Existing RecordSet if exists
    $existing = $existingRecords.where( {$_.Name -eq $zone.name -and $_.RecordType -eq $zone.type}) | Select-Object -First 1
    $noDupes = ("CNAME", "A")
    if ($existing -and ($existing.Records.ToString() -eq $zone.value -or $noDupes.Contains($_.RecordType))) {
        "Found duplicate entry: $($prettyPrint), skipping"
        continue;
    }
    
    #Peer 1 allowed duplicate A/CNAME records.  This will not stand.
    if ($zone.type -eq "CNAME" -or $zone.type -eq "A" -or $zone.type -eq "TXT") {
        $oppositeType = "A"
        if ($zone.type -eq "A" -or $zone.type -eq "TXT") {$oppositeType = "CNAME"}
        
        # Check if conflicts will occur
        $aRecord = $existingRecords.where( {$_.Name -eq $zone.name -and $_.RecordType -eq $oppositeType}) | Select-Object -First 1
        if($null -ne $aRecord -and $zone.type -eq "CNAME"){
            Write-Warning "The record $($prettyPrint) wants to write but there's an A/TXT in it's place.  Please remove and add CNAME if appropriate."
            continue
        }

        # Check if conflicts are coming
        $aRecord = $dnsZones.where({$_.name -eq $zone.name -and $_.type -eq $oppositeType}) | Select-Object -First 1
        if ($null -ne $aRecord) {
            # we're going to favor CNAME over A
            if($zone.type -ne "CNAME"){
                Write-Warning "Ignoring: ($prettyPrint) in favor of the CNAME"
                continue
            }else{Write-Host "Added this record, (A/TXT) instead of the CNAME."}
        }else {Write-Host "Couldn't find matching $($oppositeType) to $($prettyPrint) so we will enter this."}
    }

    #Populate new recordset
    $newEntry = $null
    $recordSet = $null 

    if ($zone.type -eq "AAAA" -and $existing) {
        if ($existing.Records.IPv6Address.contains($zone.value)) { 
            Write-Output "AAAA record exists $($prettyPrint), skipping"
            continue;
        }
        $recordSet = Add-AzDnsRecordConfig -RecordSet $existing  -IPv6Address $zone.value
    }
    elseif ($zone.type -eq "PTR" -and $existing) {
        if ($existing.Records.Ptrdname.contains($zone.value)) { 
            Write-Output "PTR record exists $($prettyPrint), skipping"
            continue;
        }
        $recordSet = Add-AzDnsRecordConfig -RecordSet $existing  -Ptrdname $zone.value
    }
    elseif ($zone.type -eq "TXT" -and $existing) {
        if ($existing.Records.Value.contains($zone.value)) { 
            Write-Output "TXT record exists $($prettyPrint), skipping"
            continue;
        }
        $recordSet = Add-AzDnsRecordConfig -RecordSet $existing  -Value $zone.value
    }
    elseif ($zone.type -eq "MX" -and $existing) {
        if ($existing.Records.Exchange.contains($zone.value)) { 
            Write-Output "MX record exists $($prettyPrint), skipping"
            continue;
        }
        $priority = $zone.options -replace '\D+(\d+)', '$1'
        $recordSet = Add-AzDnsRecordConfig -RecordSet $existing  -Exchange $zone.value -Preference $priority
    }
    elseif ($zone.type -eq "A") {
        $recordSet = New-AzDnsRecordConfig -IPv4Address $zone.value
    }
    elseif ($zone.type -eq "AAAA") {
        $recordSet = New-AzDnsRecordConfig -IPv6Address $zone.value
    }
    elseif ($zone.type -eq "CNAME") {
        $recordSet = New-AzDnsRecordConfig -Cname $zone.value
    }
    elseif ($zone.type -eq "PTR") {
        $recordSet = New-AzDnsRecordConfig -Ptrdname $zone.value
    }
    elseif ($zone.type -eq "TXT") {
        $recordSet = New-AzDnsRecordConfig -Value $zone.value
    }
    elseif ($zone.type -eq "MX") {
        $priority = $zone.options -replace '\D+(\d+)', '$1'
        $recordSet = New-AzDnsRecordConfig -Exchange $zone.value -Preference $priority
    }
    if ($null -ne $recordSet) {
        if ($existing) {
            $newEntry = Set-AzDnsRecordSet -Recordset $recordSet
            $existingRecords = $existingRecords.where( {$_.Name -ne $zone.name -and $_.RecordType -ne $zone.type})
            $existingRecords += $newEntry
        }
        else {
            $newEntry = New-AzDnsRecordSet -Name $zone.name -RecordType $zone.type -ZoneName $domain -ResourceGroupName $ResourceGroupName -Ttl $ttl -DnsRecords ($recordSet)
            $existingRecords += $newEntry
        }
        #check success
        if ($null -eq $newEntry) {
            Write-Error "Something didn't go well for entry: $($prettyPrint).  Please verify and make manual adjustments if required."
        }
        else {
            Write-Host "Added $($prettyPrint) with status: $($newEntry.ProvisioningState)"
        }
    }
    else {
        Write-Host "Unsupported Zone Type: $($prettyPrint).  Please import manually."
        continue
    }
    
}

Write-Host "Done importing from Csv"