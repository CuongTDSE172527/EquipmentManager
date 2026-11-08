$taskName='EquipmentManager-'+[System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$task=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if($task){Unregister-ScheduledTask -TaskName $taskName -Confirm:$false}
