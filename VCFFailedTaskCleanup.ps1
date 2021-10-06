# Script to cleanup failed tasks in SDDC Manager
# Written by Brian O'Connell - Staff Solutions Architect @ VMware

#User Variables
# SDDC Manager FQDN. This is the target that is queried for failed tasks
$sddcManagerFQDN = "lax-vcf01.lax.rainpole.io"
# SDDC Manager API User. This is the user that is used to query for failed tasks. Must have the SDDC Manager ADMIN role
$sddcManagerAPIUser = "administrator@vsphere.local"
$sddcManagerAPIPassword = "VMw@re1!"
# Password for the SDDC Manager appliance vcf user. This is used to run the task deletion
$sddcManagerVCFPassword = "VMw@re1!"



# DO NOT CHANGE ANYTHING BELOW THIS LINE
#########################################

# Set TLS to 1.2 to avoid certificate mismatch errors
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Install PowerVCF if not already installed
if (!(Get-InstalledModule -Name PowerVCF -ErrorAction SilentlyContinue)) {
    Install-Module -Name PowerVCF -MinimumVersion 2.1.5
}

# Request a VCF Token using PowerVCF
Request-VCFToken -fqdn $sddcManagerFQDN -username $sddcManagerAPIUser -password $sddcManagerAPIPassword

# Disconnect all connected vCenters to ensure only the desired vCenter is available
if ($defaultviservers) {
    $server = $defaultviservers.Name
    foreach ($server in $defaultviservers) {            
        Disconnect-VIServer -Server $server -Confirm:$False
    }
}

# Retrieve the Management Domain vCenter Server FQDN
$vcenterFQDN = ((Get-VCFWorkloadDomain | where-object {$_.type -eq "MANAGEMENT"}).vcenters.fqdn)
$vcenterUser = (Get-VCFCredential -resourceType "PSC").username
$vcenterPassword = (Get-VCFCredential -resourceType "PSC").password

# Retrieve SDDC Manager VM Name
if ($vcenterFQDN) {
    Write-Output "Getting SDDC Manager Manager VM Name"
    Connect-VIServer -server $vcenterFQDN -user $vcenterUser -password $vcenterPassword | Out-Null
    $sddcmVMName = ((Get-VM * | Where-Object {$_.Guest.Hostname -eq $sddcManagerFQDN}).Name)              
}

# Retrieve a list of failed tasks
$failedTaskIDs = @()
$ids = (Get-VCFTask -status "Failed").id
Foreach ($id in $ids) {
    $failedTaskIDs += ,$id
}
# Cleanup the failed tasks
Foreach ($taskID in $failedTaskIDs) {
    $scriptCommand = "curl -X DELETE 127.0.0.1/tasks/registrations/$taskID"
    Write-Output "Deleting Failed Task ID $taskID"
    $output = Invoke-VMScript -ScriptText $scriptCommand -vm $sddcmVMName -GuestUser "vcf" -GuestPassword $sddcManagerVCFPassword

# Verify the task was deleted    
    Try {
    $verifyTaskDeleted = (Get-VCFTask -id $taskID)
    if ($verifyTaskDeleted -eq "Task ID Not Found") {
        Write-Output "Task ID $taskID Deleted Successfully"
    }
}
    catch {
        Write-Error "Something went wrong. Please check your SDDC Manager state"
    }
}
Disconnect-VIServer -server $vcenterFQDN -Confirm:$False
