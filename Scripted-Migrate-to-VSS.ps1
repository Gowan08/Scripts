
#Moves all VMs from Distributed Port Groups to Standard Port Groups as defined by an input translation table.  Designed to use the output translation table from Make-VSS.ps1
#Author: Jason Coleman (virtuallyjason.blogspot.com)
#Usage: Move-to-VSS.ps1 -h [the target ESXi host]
param
(
	[alias("d")]
	[string]$Directory =  "Enter your Directory provided at the end of the Get-vCenterFoundation Script",
    [alias("vc")]
	$vCenter = "Enter the vCenter of the VIServer you would like to migrate all VMs to a VSS on"
)

#Trim and set target directory for where the exported files exist
$directory = $directory.trim("\")

#Set location of input file
$inputFile = "$Directory\GlobalSettings\$vCenter-PGTranslations.xml"

Add-PSSnapin VMWare*
Connect-VIServer -Server $vCenter
#Build the Hashtable
$pgHash = @{}
$allPGs = import-clixml $inputFile -ErrorAction Stop
foreach ($VMHost in ($allPGs.host | Get-Unique)){
    foreach ($thisPG in $allPGs)
    {
	    $pgHash.add($thisPG.dVSPG, $thisPG.VSSPG)
    }

    #Sets all VMs on the Host to the new VSS Port groups based on the Hashtable
    $thisHost = get-vmhost $VMhost
    foreach ($thisVM in ($thisHost | get-VM ))
    {
	    foreach ($thisNIC in ($thisVM | Get-NetworkAdapter))
	    {
		    if ($pgHash[$thisNIC.NetworkName])
		    {
			    if ($portGroup = $thisHost | get-virtualportgroup -name $pgHash[$thisNIC.NetworkName])
			    {
				    $thisNIC | set-networkadapter -confirm:$false -portgroup $portGroup
			    }
			    else
			    {
				    write-host "$($pgHash[$thisNIC.NetworkName]) does not exist."
			    }
		    }
		    else
		    {
			    echo "$($thisVM.name) $($thisNIC.Name) uses $($thisNIC.NetworkName), which not have a match in the Hash Table."
		    }
	    }
    }
}