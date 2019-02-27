# AzureDnsTools
This is a library of a few Powershell scripts written to interact with Azure DNS Zones.  There are two scripts currently, one to bulk import records into a dns zone and one to bulk remove records from a dns zone.

## Getting Started

These Powershell scripts rely on the [Az Powershell Module](https://docs.microsoft.com/en-us/powershell/azure/new-azureps-module-az?view=azps-1.4.0).  If you currently have the AzureRM Module installed, please follow the above link to learn how to upgrade to the new module.

### Prerequisites

[Az Powershell Module](https://docs.microsoft.com/en-us/powershell/azure/install-az-ps?view=azps-1.4.0)

```
Install-Module -Name Az -AllowClobber
```
# MigrateZones.ps1

### Description
This script bulk imports zone records into an Azure DNS Zone using a csv file.

If the DNS Zone does not exist in the selected subscription, the script will prompt to automatically create the domain.

_Let's get real_.  I wrote this script to move away from a company called Peer 1.  They allowed duplicate CNAME and A records, which is technically not allowed.  Because of this, I have a check in here to avoid an Azure error that I'd like to talk about.  If you have a duplicate CNAME and A record, the script will output an error and keep going, so **check your logs**.  It will favor the A record over the CNAME due to performance gains.  In the extremely unlikely event of the A and CNAME values being equal, it will omit a warning.  More likely though, it will omit an error for you to check which one is correct.

### Prerequisites
The csv file should have the following headers:
- name
-- The record name (@, *, www, etc)
- ttl
-- Time to Live
- type
-- Record Type (CNAME, A, TXT, etc)
- options
-- Options for special records, like priority for MX
- value
-- Record Value

## Fields
```
MigrateZones -FileName <string> -ResourceGroupName <string> [-SubscriptionId <string>] [-OverrideDomainName <string>]  [-DefaultTtl <int32>]
```
##Parameters

### -FileName
The FileName of the csv for bulk importing.  This file needs the headers mentioned above.  It will error out if the header is not found or if they are wrong.  By default, the filename can be the target dns zone name (ie, the domain).  For example, "example.com" can be inferred from "example.com.csv".

For the record name, it is ok to have the full host name in there (ex. www.example.com).  It will strip `example.com` from the host name and just select `www` as the record name.

### -ResourceGroupName
Resource Group the DNS Zone belongs to.

### -OverrideDomainName
Supplying a domain name to this parameter will make the script ignore inferring the domain from the filename.

### -DefaultTtl
Specify a value for Ttl when it is missing in the csv field.  This parameter is optional and defaults to 1 hour.

### -Force
Will force dialogs to yes answers.  There are 2 possible dialogs: One to confirm the domain if inferred from the filename and one to create a DNS Zone that doesn't exist.

### -SubscriptionId
Optional Parameter to select a subscription id upon Azure login.

## Output
The script outputs info, warning, and error lines depending upon the result of an Azure command.  You can pipe this to a file if you'd like.  It logs every action it takes.

## Example

Given the following csv file as `example.com.csv`:
```
name,ttl,type,options,value
example.com,300,A,,52.237.18.220
mail.example.com,300,A,,208.49.44.54
news.example.com,3600,A,,209.15.250.176
www.example.com,,CNAME,,example-app.azurewebsites.net
example.com,3600,TXT,,example-app.azurewebsites.net
example.com,3600,MX,priority: 10,mail.example.com
www.example.com,,CNAME,,example-news-app.azurewebsites.net
```

We can run:
```
./MigrateDomains.ps1 -ResourceGroupName example-prod -FileName example.com.csv
```
This will infer the domain from the file name and import the records into the DNS Zone.  This is the simplest way to run the script.

With results in Azure showing:
Name | Type | Ttl | Options | Record
--- | --- | --- | --- | ---
@ | A | 300 |  | 10.1.1.2
mail | A | 300 | | 10.1.1.3
news | A | 3600 | | 10.1.1.4
www | CNAME | **3600** | | example-app.azurewebsites.net
@ | TXT | 3600 | | example-app.azurewebsites.net
example.com | MX | 3600 | 10 | mail.example.com

*Notice* the bold ttl in the table above for the CNAME entry.  In the csv, it was missing, so the default ttyl was used.

*Also Notice* The last CNAME entry from the csv file is not in the list.  It will have produced an error in the output because there is a matching A record for "@".

# ClearAlLDnsRecords.ps1

### Description
This script will clear records from a dns zone in Azure based on an optional type filter.  This automatically ignores SOA and NS records.

### Prerequisites

None

## Fields
```
ClearAllDnsRecords -ResourceGroupName <string> -DnsZoneName <string> [-SubscriptionId <string>] [-RecordTypes <string>]
```
##Parameters

### -ResourceGroupName
The resource group the DNS Zone belongs to

### -DnsZoneName
The DNS Zone Name for the target zone to remove records from.

### -SubscriptionId
Optionally specify Subscription for this zone.

### -RecordTypes
Comma seperated values of record types to filter by.  This parameter is `optional` and, if omitted, all record types will be selected.

## Output
The script outputs info, warning, and error lines depending upon the result of an Azure command.  You can pipe this to a file if you'd like.  It logs every action it takes.

## Example

We can run:
```
./ClearAllDnsRecords.ps1 -ResourceGroupName example-prod -ResourceTypes "MX,A"
```
This will grab all records that have an MX or A type and remove them.  If we have the above records from example.com, we would remove the below:

Name | Type | Ttl | Options | Record
--- | --- | --- | --- | ---
www | CNAME | **3600** | | example-app.azurewebsites.net
@ | TXT | 3600 | | example-app.azurewebsites.net
