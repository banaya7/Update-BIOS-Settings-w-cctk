 <#
 Author: Brandon Anaya
 Date: 05/05/2025
 Purpose: This code is paired with a batch file and an ini file that together allow for the automation of setting BIOS Settings 
    using Dell's CCTK executables. This code copies a directory that holds the CCTK executable, and the Batch file that executes
    the executable to the C:\temp directory of each computer on the list. It then executes the batch file which Flash's the BIOS
    Settings. It then logs the completion of the BIOS Flash. The powershell command then grabs the local logs, and appends then 
    appends them to a master log file. The script then deletes all resources besides the local logs on the remote computers, and
    Restarts all computers on the ini list. 
 Needed: Set your variables, download Dell CCTK, get an executable that holds desired settings you wish to copy, gather all
    resources, (Note: Everything can be stored either on a network drive, or your computer) and execute powershell command.  
 
 
  Define the path to the:
  - Configuration file: This will be an ini file that will hold the list of the computers to run the computer on. 
  - PSExec path: Download this online. You usually will not need to change the path.
  - Batch Source: This is the path of the directory where the CCTK files and the Batch file will sit.
  - BIOS Source: This is the path of the directory that the Dell CCTK GUI creates when you capture the BIOS settings of a computer.
  - Batch File: This is the name of the batch file that gets locally copied onto the machine that exectutes the BIOS flash.
 #>
 $iniPath = "[An ini file with the list of your computers, or pointing to a list of computers]"
 $psExecPath = "C:\PSTools\PsExec.exe"
 $batchSource = "[Directory where your Batch file lies(Can be in a network share)]"
 $biosSource = "[Directory where your CCTK executable lies(Can be in a network share)]"
 $batchFile = "[The name of your batch file]"
 
 
 Write-Host "Reading from config: $iniPath"
 
 # Read the INI file
 $iniContent = Get-Content -Path $iniPath
 
 # Extract the computer list path
 $computerListFilePath = $iniContent | Where-Object { $_ -match "^ComputerList=" } | ForEach-Object { $_.Split('=')[1] }
 
 # Validate and load computer list
 if (-not (Test-Path $computerListFilePath)) {
     Write-Host "[ERROR] Computer list file not found: $computerListFilePath"
     exit
 }
 
 $computers = Get-Content -Path $computerListFilePath
 Write-Host "Computers to update: $($computers -join ', ')"
 
 # Loop through each computer and copy files
 foreach ($computer in $computers) {
    Write-Host "Copying files to $computer..."
 
    # Copy BIOS folder
    try {                                              #\/ Name your destination
        robocopy $biosSource "\\$computer\C$\Temp\[NAME OF DESTINATION DIRECTORY]" /E /Z /R:2 /W:2
        Write-Host "BIOS folder copied to $computer"
    } catch {
        Write-Warning "Failed to copy BIOS folder to ${computer}: $_"
    }
 
   
    # Copy BIOS_BATCH_V2.bat
    try {
    Copy-Item -Path "$batchSource\$batchFile" -Destination "\\$computer\C$\Temp\" -Force
    Write-Host "Batch file copied to $computer"
    } catch {
    Write-Warning "Failed to copy BIOS_BATCH_V2.bat to ${computer}: $_"
    }
 
 
     Write-Host "Done with $computer"
     Write-Host ""
 }
 
 Write-Host "All files copied successfully."
 
 # Wait before executing BIOS update
 Start-Sleep -Seconds 30
 
 # Execute BIOS update remotely
 foreach ($computer in $computers) {
     Write-Host "n=== Updating BIOS on $computer ==="
     $remoteBatchPath = "C:\Temp\$batchFile"
 
     try {
         & $psExecPath -accepteula \\$computer -h -s -d $remoteBatchPath
         Write-Host "BIOS update triggered on $computer"
     } catch {
         Write-Warning "Failed to trigger BIOS update on ${computer}: $_"
     }
 }
 
 # Wait before collecting logs
 Start-Sleep -Seconds 30
 
 foreach ($computer in $computers) {
    Write-Host "=== Processing $computer ==="
    $remoteLogPath = "\\$computer\C$\Temp\BIOSFLASHLOGS.txt"
 
    try {
        if (Test-Path $remoteLogPath) {
            Add-Content -Path $masterLog -Value "===== $computer BIOS Log ====="
            Get-Content $remoteLogPath | Add-Content -Path $masterLog
            Add-Content -Path $masterLog -Value "`n-------------------------------`n"
            Write-Host " Log collected from $computer"
        }
        else {
            Add-Content -Path $masterLog -Value "$computer - No BIOS log found`n"
            Write-Warning "$computer - BIOS log not found"
        }
    } catch {
        Write-Warning " Error collecting log from ${computer}: $_"
    }
 }
 
 foreach ($computer in $computers) {
    Write-Host "=== Cleaning files on $computer ==="
   
    $pathsToDelete = @(
        "\\$computer\C$\Temp\[NAME OF DESTINATION DIRECTORY]",
        "\\$computer\C$\Temp\BIOS_BATCH_V2.bat"
    )
 
    foreach ($item in $pathsToDelete) {
        try {
            if (Test-Path $item) {
                Remove-Item $item -Recurse -Force
                Write-Host "Deleted: $item"
            } else {
                Write-Host "Not found: $item"
            }
        } catch {
            Write-Warning "Failed to delete $item on ${computer}: $_"
        }
    }
 
    Write-Host ""
 }
 
 
 # Wait before rebooting
 Start-Sleep -Seconds 10
 
 
 # Reboot all updated computers
 foreach ($computer in $computers) {
     Write-Host "=== Rebooting $computer ==="
     try {
         Start-Process -NoNewWindow -FilePath "$psExecPath" -ArgumentList "\\$computer -s shutdown /r /f /t 0"
     } catch {
         Write-Warning "Failed to reboot ${computer}: $_"
     }
 }
 
 Write-Host "n=== BIOS Update Process Complete ==="
