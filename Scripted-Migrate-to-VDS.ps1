#Moves all Host's VMs back to their starting DVS.
param
(
	[alias("d")]
	[string]$Directory =  "Enter your Directory provided at the end of the Get-vCenterFoundation Script",
    [alias("vc")]
	$vCenter = "Enter the Destination vCenter where you would like to migrate all VMs to a VDS on"
)
Add-PSSnapin VMWare*

#Trim and set target directory for where the exported files exist
$directory = $directory.trim("\")

#Get Old vCenter with Split-Path
$oldvCenter = $Directory | Split-Path -Leaf

#Set location of input file
$inputFile = "$Directory\GlobalSettings\$oldvCenter-PGTranslations.xml"

#Use PortGroup information to get all Hosts ready to be migrated
$allPGs = import-clixml $inputFile -ErrorAction Stop

cls

Try{
Write-Host "Connecting to Destination vCenter" -ForegroundColor Yellow
Connect-VIServer -Server $vCenter -WarningAction SilentlyContinue -erroraction Stop | Out-Null
}
Catch{
Write-Host "Connection to Destination vCenter failed, most likely due to a network error or incorrect credentials, please re-run the script with the correct parameters and try again" -ForegroundColor Red
exit
}

#successful connection message
Write-Host "Connection to Destination established successfully!" -ForegroundColor Green

$pgHash = @{}

foreach ($thisPG in $allPGs)
{
	$pgHash.add($thisPG.VSSPG, $thisPG.dVSPG)
}

#Sets all VMs on the Host to the new VDS Port groups based on the Hashtable
foreach ($VMHost in ($allPGs.host | Get-Unique)){
    foreach ($thisVM in (get-VMhost -name $VMHost | get-VM ))
    {
	    foreach ($thisNIC in ($thisVM | Get-NetworkAdapter))
	    {
		    if ($pgHash[$thisNIC.NetworkName])
		    {
			    if ($portGroup = get-vdportgroup -name $pgHash[$thisNIC.NetworkName] -erroraction SilentlyContinue)
			    {
				    $thisNIC | set-networkadapter -confirm:$false -portgroup $portGroup
			    }
			    else
			    {
				    echo "$($thisVM.name) $($thisNIC.Name) uses $($thisNIC.NetworkName), which not have a match in the DVS."
			    }
		    }
		    else
		    {
			    echo "$($thisVM.name) $($thisNIC.Name) uses $($thisNIC.NetworkName), which not have a match in the Hash Table."
		    }
	    }
    }
}