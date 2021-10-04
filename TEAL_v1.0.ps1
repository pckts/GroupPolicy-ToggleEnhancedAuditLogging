#Imports neccesary modules
Import-Module -Name GroupPolicy | Out-Null
Import-Module -Name ActiveDirectory | Out-Null

#Creates working directory
New-Item -ItemType "directory" -Path "C:\TEAL" -Force | Out-Null

#Import GPO and bind everywhere
$GPOName = "TEAL_ToggleEnhancedAuditLogging" | Out-Null
$Partition = Get-ADDomainController | select-object DefaultPartition | Out-Null
$GPOSource = "C:\TEAL" | Out-Null
import-gpo -BackupId "166D2DD0-AE7C-425F-934A-CC84BA44EEFA" -TargetName $GPOName -path $GPOSource -CreateIfNeeded | Out-Null
Get-GPO -Name $GPOName | New-GPLink -Target $Partition.DefaultPartition | Out-Null
Set-GPLink -Name $GPOName -Enforced Yes -Target $Partition.DefaultPartition | Out-Null
$Blocked = Get-ADOrganizationalUnit -Filter * | Get-GPInheritance | Where-Object {$_.GPOInheritanceBlocked} | select-object Path | Out-Null
foreach ($B in $Blocked) | Out-Null
{
    New-GPLink -Name $GPOName -Target $B.Path | Out-Null
    Set-GPLink -Name $GPOName -Enforced Yes -Target $B.Path | Out-Null
}

#Create and import WMI Filter
$MOF = @' 

instance of MSFT_SomFilter
{
	Author = "packet@intern.mtossen.com";
	ChangeDate = "20211004201644.604000-000";
	CreationDate = "20211004201639.198000-000";
	Domain = "intern.mtossen.com";
	ID = "{63363B2D-E917-4F58-A861-3E9203A1B281}";
	Name = "ITR_AllServers";
	Rules = {
instance of MSFT_Rule
{
	Query = "SELECT * FROM Win32_OperatingSystem WHERE PoductType = \"2\" OR ProductType = \"3\"";
	QueryLanguage = "WQL";
	TargetNameSpace = "root\\CIMv2";
}};
}; 
'@ | Out-Null
$mof | out-file C:\TEAL\ITR_AllServers.mof | Out-Null
mofcomp -N:root\Policy "C:\TEAL\TEAL_AllServers.mof" | Out-Null

#Sets WMI filter on GPO
$WMIFilterName = "TEAL_AllServers" | Out-Null
$GroupPolicyName = "TEAL_ToggleEnhancedAuditLogging" | Out-Null
$GPdomain = New-Object Microsoft.GroupPolicy.GPDomain | Out-Null
$SearchFilter = New-Object Microsoft.GroupPolicy.GPSearchCriteria | Out-Null
$allWmiFilters = $GPdomain.SearchWmiFilters($SearchFilter) | Out-Null
$WMIfilter = $allWmiFilters | Where-Object Name -eq $WMIFilterName | Out-Null
$GroupPolicyObject = $null | Out-Null
$GroupPolicyObject = Get-GPO -Name $GroupPolicyName | Out-Null
$GroupPolicyObject.WmiFilter = $WMIfilter | Out-Null

#Deletes working directory
Remove-Item C:\TEAL -Recurse -Force | Out-Null
