[CmdletBinding()]
Param(
    [Boolean]$UEFI
)

# Password
$process = Start-Process -FilePath ".\cctk.exe" -ArgumentList "--setuppwd=password" -NoNewWindow -Wait -PassThru
If($process.ExitCode -ine 0) {
    ## catch not 0 error code
    Exit $process.ExitCode
}


# TPM
## if non-zero exit code, continue
$tpm_array = @("--tpm=on","--tpmactivation=activate")
foreach ($command in $tpm_array) {
    If($(Start-Process -FilePath ".\cctk.exe" -ArgumentList "--valsetuppwd=password $command" -NoNewWindow -Wait -PassThru).ExitCode -ine 0) {
        Write-Host "$command, continuing..."
        Continue
    }
}


# tries to enable UEFI, if any of the settings fail, revert to legacy.
# UEFI
$boot2legacy = $false

$UEFI_array = @("bootorder --activebootlist=uefi",
           "--legacyorom=disable",
           "--secureboot=enable",
           "--uefinwstack=enable",
           "--forcepxeonnextboot=enable")
foreach ($command in $UEFI_array) {
    If($command -eq "--secureboot=enable") {
        $secureboot_exitcode = $(Start-Process -FilePath ".\cctk.exe" -ArgumentList "--valsetuppwd=password $command" -NoNewWindow -Wait -PassThru).ExitCode
        If($secureboot_exitcode -eq 119) {
            # BIOS does not support secure boot
            Write-Host "$command, breaking..."
            $boot2legacy = $true
            Break
        } ElseIf (($secureboot_exitcode -eq 188) -or ($secureboot_exitcode -eq 0)) {
            # Secure boot is enabled, continue on
            Continue
        } Else {
            # catch non-zero error code
            Write-Host "$command, exiting..."
            Exit $secureboot_exitcode
        }
    } ElseIf($command -eq "--uefinwstack=enable") {
        If($secureboot_exitcode -eq 253) {
            Write-Host "No explicit support of uefi network, assuming it supports it, continuing..."
            Continue
        }
    } Else {
        If($(Start-Process -FilePath ".\cctk.exe" -ArgumentList "--valsetuppwd=password $command" -NoNewWindow -Wait -PassThru).ExitCode -ine 0) {
            Write-Host "$command, breaking..."
            $boot2legacy = $true
            Break
        }
    }
}

# Legacy
If($boot2legacy) {
    $process = Start-Process -FilePath ".\cctk.exe" -ArgumentList "--valsetuppwd=password bootorder --activebootlist=legacy" -NoNewWindow -Wait -PassThru
    If($process.ExitCode -ine 0) {
        # catch non-zero error code
        Write-Host "$command, exiting..."
        Exit $process.ExitCode
    }
}

# remove BIOS password
$process = Start-Process -FilePath ".\cctk.exe" -ArgumentList "--valsetuppwd=password --setuppwd=" -NoNewWindow -Wait -PassThru

# reboots only if changed from Legacy to UEFI or UEFI to Legacy
If(((-not $boot2legacy) -and ($UEFI -eq $false)) -or (($boot2legacy) -and ($UEFI -eq $true))) {
    Write-Host "Reboot"
    wpeutil.exe reboot
} Else {
    Exit 0
}
