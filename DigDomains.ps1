param (   
    [Parameter(Mandatory = $true)]
    [string]$FileName,
    [string]$AzureNameServers
)
$csv = Import-Csv $FileName | Select-Object *,@{Name='AzureDnsFound';Expression={''}} | Select-Object *,@{Name='AzureValue';Expression={''}}
if(!$csv){
    Write-Warning "Couldn't import Csv File"
    exit
}

# Validate Properties exist
$nameProp = $csv | Get-Member -Name name
$typeProp = $csv | Get-Member -Name type
if($null -eq $nameProp -or $null -eq $typeProp){
    Write-Warning "Required fields name and/or type missing. Please fix csv and try again."
    exit
}

$compareProp = $csv | Get-Member -Name value
$compare = $true
if($null -eq $compareProp){
    $compare = $false
}

$output = @()
$NameServers =  New-Object System.Collections.ArrayList($null)

if([string]::IsNullOrEmpty($AzureNameServers)){
    for($i = 1; $i -lt 7; $i++){
        [void]$NameServers.Add("ns1-0$($i).azure-dns.com")
    }
} else{
    [void]$NameServers.AddRange($AzureNameServers.Split(","))
}

foreach($zone in $csv){
    $foundNs = "none"
    Write-Output "Input: $($zone.name) / $($zone.type) / $($zone.value)"
    foreach($ns in $NameServers){
        if($zone.name.startswith("*")){
            $output = Resolve-DnsName -Name $zone.name.replace("*", "asdf1234asdf") -Server $ns -Type $zone.type
        }else{
            $output = Resolve-DnsName -Name $zone.name -Server $ns -Type $zone.type
        }
        if($null -ne $output){
            $foundNs = $ns
            break
        }
    }
    Write-Output "Output: $($output.Name) / $($output.Type) / $($output.Text)"
    [string]$writeToFile
    if($null -eq $output){
        $writeToFile = "COULD NOT RESOLVE"
    }elseif($output[0].Type -eq "CNAME" -and ($zone.type -eq "A" -or $zone.type -eq "TXT")){
        $writeToFile = "Resolved to CNAME: $($output[0].NameHost)"
    }elseif($output[0].Type -eq "SOA" -and $zone.type -ne "SOA"){
        $writeToFile = "Could not find entry"
    }
    elseif($output[0].Type -eq $zone.type){
        if($zone.type -eq "A"){
            $writeToFile = $output[0].IpAddress
        } elseif($zone.type -eq "TXT"){
            if($compare){
                $writeToFile = $output.Strings | Where-Object {$_ -eq $zone.value}
                if(!$writeToFile){$writeToFile = $output[0].Text}
            } else {
                $writeToFile = $output[0].Text -join ", "
            }
        } elseif($zone.type -eq "CNAME"){
            $writeToFile = $output[0].NameHost
        } elseif($zone.type -eq "NS" -and $output[0].Type -eq "NS"){
            $writeToFile = $output[0].NameHost -join ", "
        } elseif($zone.type -eq "MX"){
            $writeToFile = $output[0].NameExchange
        } else{
            $writeToFile = "Couldn't determine what to write for $($output[0].Name) / $($output[0].Type)"
        }
    } else{
        $writeToFile = "Non-matching Result Type"
    }
    $zone.AzureValue = $writeToFile
    $zone.AzureDnsFound = $foundNs
}
$ext = [System.IO.Path]::GetExtension($FileName)
$newFileName = $FileName.Substring(0, $FileName.Length-$ext.Length) + "-results" + $ext
$csv | Export-Csv $newFileName -NoType