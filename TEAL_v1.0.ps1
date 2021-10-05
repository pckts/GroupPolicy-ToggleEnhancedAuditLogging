#By packet

#Require run as admin
#Requires -RunAsAdministrator

#Sets the TLS settings to allow downloads via HTTP
#Downloads, installs, and imports neccesary modules
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = "SilentlyContinue"
Import-Module -Name GroupPolicy | Out-Null
Import-Module -Name ActiveDirectory | Out-Null

#Tries to import archive module before installing, as installing takes a long time.
try
{
    import-module Microsoft.powershell.archive | out-null
}
catch
{
    install-module Microsoft.powershell.archive | out-null
}

#Create working directory
New-Item -ItemType "directory" -Path C:\TEAL | Out-Null
sleep 1

#Downloads GPO and unzips it into working directory
$GPOURL = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("aHR0cHM6Ly9naXRodWIuY29tL3Bja3RzL1RFQUwvYmxvYi9tYWluL1RFQUxfR1BPLnppcA=="))
Invoke-WebRequest -Uri $GPOURL -OutFile C:\TEAL\GPO.zip | Out-Null
sleep 1
Expand-Archive -LiteralPath 'C:\TEAL\GPO.zip' -DestinationPath C:\TEAL

#Import GPO and bind everywhere
$GPOName = "TEAL_ToggleEnhancedAuditLogging"
$Partition = Get-ADDomainController | select-object DefaultPartition
$GPOSource = "C:\TEAL"
import-gpo -BackupId "9D866446-09D5-43E2-A97B-86C0C9C6C6F5" -TargetName $GPOName -path $GPOSource -CreateIfNeeded | Out-Null
Get-GPO -Name $GPOName | New-GPLink -Target $Partition.DefaultPartition | Out-Null
Set-GPLink -Name $GPOName -Enforced Yes -Target $Partition.DefaultPartition | Out-Null
$Blocked = Get-ADOrganizationalUnit -Filter * | Get-GPInheritance | Where-Object {$_.GPOInheritanceBlocked} | select-object Path
foreach ($B in $Blocked)
{
    New-GPLink -Name $GPOName -Target $B.Path | Out-Null
    Set-GPLink -Name $GPOName -Enforced Yes -Target $B.Path | Out-Null
}

#Creates WMI filter
$MOF = @' 

instance of MSFT_SomFilter
{
	Author = "packet@teal.teal";
	ChangeDate = "20211004201644.604000-000";
	CreationDate = "20211004201639.198000-000";
	Domain = "TEAL.TEAL";
	ID = "{62806280-4A95-4178-A48F-14A2E4871BB8}";
	Name = "TEAL_AllServers";
	Rules = {
instance of MSFT_Rule
{
	Query = "SELECT * FROM Win32_OperatingSystem WHERE PoductType = \"2\" OR ProductType = \"3\"";
	QueryLanguage = "WQL";
	TargetNameSpace = "root\\CIMv2";
}};
}; 
'@
$mof | out-file C:\TEAL\TEAL_AllServers.mof

#Imports WMI filter
mofcomp -N:root\Policy "C:\TEAL\TEAL_AllServers.mof" | Out-Null

#Sets WMI filter on GPO
$WMIFilterName = "TEAL_AllServers"
$GroupPolicyName = "TEAL_ToggleEnhancedAuditLogging"
$GPdomain = New-Object Microsoft.GroupPolicy.GPDomain
$SearchFilter = New-Object Microsoft.GroupPolicy.GPSearchCriteria
$allWmiFilters = $GPdomain.SearchWmiFilters($SearchFilter)
$WMIfilter = $allWmiFilters | Where-Object Name -eq $WMIFilterName
$GroupPolicyObject = $null
$GroupPolicyObject = Get-GPO -Name $GroupPolicyName
$GroupPolicyObject.WmiFilter = $WMIfilter

#Deletes working directory
Remove-Item C:\TEAL -Recurse -Force | Out-Null
