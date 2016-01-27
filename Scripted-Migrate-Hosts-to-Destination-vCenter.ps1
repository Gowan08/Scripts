#Moves all Hosts from one vCenter to another.
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

$dc = Get-Datacenter
$DefaultDir = $dc[0]

#successful connection message
Write-Host "Connection to Destination established successfully!" -ForegroundColor Green

#Ask if root password is the same
$samepw = read-host "Do you have the same password for all hosts? (Type yes or no)"

if($samepw -like "Y*" -or $samepw -like "y*"){
Write-Host "Enter the standardized root password" -ForegroundColor Yellow
$rootpw = Get-Credential
}
Else{Write-Host "Unfortunatly, you will have to type a password for each host :(" -ForegroundColor Yellow}

if($samepw -like "Y*" -or $samepw -like "y*"){
    foreach ($VMHost in ($allPGs.host | Get-Unique)){
    Write-Host "Adding $VMHost to $vCenter using supplied credentials" -ForegroundColor Green
    Add-VMHost -Name $VMhost -Location $DefaultDir -Credential $rootpw -Force | Out-Null
    }
}
Else{
	foreach ($VMHost in ($allPGs.host | Get-Unique)){
	Write-Host "Adding $VMHost to $vCenter using supplied credentials" -ForegroundColor Green
	Add-VMHost -Name $VMhost -Location $DefaultDir -Force
	}
}





