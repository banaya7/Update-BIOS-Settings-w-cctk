# Define the path to the configuration file
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
