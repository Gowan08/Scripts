#Run on destination vCenter to recreate Roles and Permissions
param
(
	[alias("d")]
	$directory = "Enter where you saved the files",
)
$directory = $directory.trim("\")
#Read in Permissions from Get-SourceRolesPerms.ps1 script and assign those permissions
foreach ($thisPerm in (import-clixml $directory\permissions.xml)) {get-folder $thisPerm.entity.name | new-vipermission -role $thisPerm.role -Principal $thisPerm.principal -propagate $thisPerm.Propagate}
$allPerms = import-clixml $directory\permissions.xml
foreach ($thisPerm in $allPerms) {get-datacenter $thisPerm.entity.name | new-vipermission -role $thisPerm.role -Principal $thisPerm.principal -propagate $thisPerm.Propagate}