#Copies all Port Groups from a Distributed vSwitch to a Standard vSwitch
#Orginal Author: Jason Coleman (virtuallyjason.blogspot.com)
#Usage: Scripted-Make-VSS.ps1 Create a virtual Standard switch on all esxi hosts within a vCenter.
param
(
	[alias("d")]
	$directory = "Please enter the directory of where you would like the portgroup translations xml to save to",
	[alias("dc")]
	$vCenter = "Please enter the vCenter you would like to apply this script too"
)

$VMHosts = Get-VMHost

foreach($VMHost in $VMHosts){
    $VDSs = Get-VMHost $VMhost | Get-VDSwitch
    foreach($VDS in $VDSs){
        $vss = $VDS.Name
        IF(!(Get-VirtualSwitch -VMHost $VMHost -Name $vss -Standard)){
        New-VirtualSwitch  -VMHost $VMHost -Name $vss -ErrorAction SilentlyContinue
        #Create an empty array to store the port group translations
        $pgTranslations = @()
        #Get the destination vSwitch
        $destSwitch = Get-VirtualSwitch -host $VMHost -name $vss -Standard
        #Get a list of all port groups on the source distributed vSwitch
        $allPGs = get-vdswitch -name $VDS | get-vdportgroup
        foreach ($thisPG in $allPGs)
        {
            $thisObj = new-object -Type PSObject
            $thisObj | add-member -MemberType NoteProperty -Name "dVSPG" -Value $thisPG.Name
            $thisObj | add-member -MemberType NoteProperty -Name "VSSPG" -Value "$($thisPG.Name)-VSS"
            new-virtualportgroup -virtualswitch $destSwitch -name "$($thisPG.Name)-VSS"
            # Ensure that we don't try to tag an untagged VLAN
            if ($thisPG.vlanconfiguration.vlanid)
            {
	            get-virtualportgroup -virtualswitch $destSwitch -name "$($thisPG.Name)-VSS" | Set-VirtualPortGroup -vlanid $thisPG.vlanconfiguration.vlanid
            }
            $pgTranslations += $thisObj
        } 
        $pgTranslations | export-clixml $GlobalDir\$outputFile
        }
        Else{
        Write-Host "Somehow, a standard vSwitch named $vss already existed with the exact same name, what are the odds! Not continuing forward on $VMHost." -ForegroundColor Yellow
        break
        }
    }
}