# Export source Roles/Permissions
param
(
	[alias("d")]
	$directory = "Enter where you would like to save the files",
)
$directory = $directory.trim("\")
new-item $directory -type directory -erroraction silentlycontinue
get-virole | where {$_.issystem -eq $false} | export-clixml $directory\roles.xml
Get-VIPermission | export-clixml $directory\permissions.xml
