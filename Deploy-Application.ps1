<#
.SYNOPSIS
	This script performs the installation or uninstallation of an application(s).
	# LICENSE #
	PowerShell App Deployment Toolkit - Provides a set of functions to perform common application deployment tasks on Windows.
	Copyright (C) 2017 - Sean Lillis, Dan Cunningham, Muhammad Mashwani, Aman Motazedian.
	This program is free software: you can redistribute it and/or modify it under the terms of the GNU Lesser General Public License as published by the Free Software Foundation, either version 3 of the License, or any later version. This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
	You should have received a copy of the GNU Lesser General Public License along with this program. If not, see <http://www.gnu.org/licenses/>.
.DESCRIPTION
	The script is provided as a template to perform an install or uninstall of an application(s).
	The script either performs an "Install" deployment type or an "Uninstall" deployment type.
	The install deployment type is broken down into 3 main sections/phases: Pre-Install, Install, and Post-Install.
	The script dot-sources the AppDeployToolkitMain.ps1 script which contains the logic and functions required to install or uninstall an application.
.PARAMETER DeploymentType
	The type of deployment to perform. Default is: Install.
.PARAMETER DeployMode
	Specifies whether the installation should be run in Interactive, Silent, or NonInteractive mode. Default is: Interactive. Options: Interactive = Shows dialogs, Silent = No dialogs, NonInteractive = Very silent, i.e. no blocking apps. NonInteractive mode is automatically set if it is detected that the process is not user interactive.
.PARAMETER AllowRebootPassThru
	Allows the 3010 return code (requires restart) to be passed back to the parent process (e.g. SCCM) if detected from an installation. If 3010 is passed back to SCCM, a reboot prompt will be triggered.
.PARAMETER TerminalServerMode
	Changes to "user install mode" and back to "user execute mode" for installing/uninstalling applications for Remote Destkop Session Hosts/Citrix servers.
.PARAMETER DisableLogging
	Disables logging to file for the script. Default is: $false.
.EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -DeployMode 'Silent'; Exit $LastExitCode }"
.EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -AllowRebootPassThru; Exit $LastExitCode }"
.EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -DeploymentType 'Uninstall'; Exit $LastExitCode }"
.EXAMPLE
    Deploy-Application.exe -DeploymentType "Install" -DeployMode "Silent"
.NOTES
	Toolkit Exit Code Ranges:
	60000 - 68999: Reserved for built-in exit codes in Deploy-Application.ps1, Deploy-Application.exe, and AppDeployToolkitMain.ps1
	69000 - 69999: Recommended for user customized exit codes in Deploy-Application.ps1
	70000 - 79999: Recommended for user customized exit codes in AppDeployToolkitExtensions.ps1
.LINK
	http://psappdeploytoolkit.com
#>

## Suppress PSScriptAnalyzer errors for not using declared variables during AppVeyor build
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "", Justification="Suppress AppVeyor errors on unused variables below")]

[CmdletBinding()]
Param (
	[Parameter(Mandatory=$false)]
	[ValidateSet('Install','Uninstall','Repair')]
	[string]$DeploymentType = 'Install',
	[Parameter(Mandatory=$false)]
	[ValidateSet('Interactive','Silent','NonInteractive')]
	[string]$DeployMode = 'Interactive',
	[Parameter(Mandatory=$false)]
	[switch]$AllowRebootPassThru = $false,
	[Parameter(Mandatory=$false)]
	[switch]$TerminalServerMode = $false,
	[Parameter(Mandatory=$false)]
	[switch]$DisableLogging = $false
)

Try {
	## Set the script execution policy for this process
	Try { Set-ExecutionPolicy -ExecutionPolicy 'ByPass' -Scope 'Process' -Force -ErrorAction 'Stop' } Catch { Write-Error "Failed to set the execution policy to Bypass for this process." }

	##*===============================================
	##* VARIABLE DECLARATION
	##*===============================================
	## Variables: Application
	[string]$appVendor = 'Dassault Systemes'
	[string]$appName = 'SolidWorks'
	[string]$appVersion = '2023 SP2'
	[string]$appArch = 'x64'
	[string]$appLang = 'EN'
	[string]$appRevision = '01'
	[string]$appScriptVersion = '1.2.0'
	[string]$appScriptDate = '06/27/2023'
	[string]$appScriptAuthor = 'Steve Patterson'
	##*===============================================
	## Variables: Install Titles (Only set here to override defaults set by the toolkit)
	[string]$installName = ''
	[string]$installTitle = ''

	##* Do not modify section below
	#region DoNotModify

	## Variables: Exit Code
	[int32]$mainExitCode = 0

	## Variables: Script
	[string]$deployAppScriptFriendlyName = 'Deploy Application'
	[version]$deployAppScriptVersion = [version]'3.8.3'
	[string]$deployAppScriptDate = '30/09/2020'
	[hashtable]$deployAppScriptParameters = $psBoundParameters

	## Variables: Environment
	If (Test-Path -LiteralPath 'variable:HostInvocation') { $InvocationInfo = $HostInvocation } Else { $InvocationInfo = $MyInvocation }
	[string]$scriptDirectory = Split-Path -Path $InvocationInfo.MyCommand.Definition -Parent

	## Dot source the required App Deploy Toolkit Functions
	Try {
		[string]$moduleAppDeployToolkitMain = "$scriptDirectory\AppDeployToolkit\AppDeployToolkitMain.ps1"
		If (-not (Test-Path -LiteralPath $moduleAppDeployToolkitMain -PathType 'Leaf')) { Throw "Module does not exist at the specified location [$moduleAppDeployToolkitMain]." }
		If ($DisableLogging) { . $moduleAppDeployToolkitMain -DisableLogging } Else { . $moduleAppDeployToolkitMain }
	}
	Catch {
		If ($mainExitCode -eq 0){ [int32]$mainExitCode = 60008 }
		Write-Error -Message "Module [$moduleAppDeployToolkitMain] failed to load: `n$($_.Exception.Message)`n `n$($_.InvocationInfo.PositionMessage)" -ErrorAction 'Continue'
		## Exit the script, returning the exit code to SCCM
		If (Test-Path -LiteralPath 'variable:HostInvocation') { $script:ExitCode = $mainExitCode; Exit } Else { Exit $mainExitCode }
	}

	#endregion
	##* Do not modify section above
	##*===============================================
	##* END VARIABLE DECLARATION
	##*===============================================

	If ($deploymentType -ine 'Uninstall' -and $deploymentType -ine 'Repair') {
		##*===============================================
		##* PRE-INSTALLATION
		##*===============================================
		[string]$installPhase = 'Pre-Installation'

		## Show Welcome Message, close Internet Explorer if required, verify there is enough disk space to complete the install, and persist the prompt
		Show-InstallationWelcome -CloseApps 'sldProdMon,SLDWORKS,sldworks_fs' -CheckDiskSpace -PersistPrompt

		## Show Progress Message (with the default message)
		Show-InstallationProgress

		## <Perform Pre-Installation tasks here>
		## <Perform Pre-Installation tasks here>
		## We don't actually want to remove old versions since new installers can upgrade over it by default
		## THat said, if the 2022 Uninstall strings are needed:
		<#
		
		# Remove-MSIApplications -Name 'SolidWorks 2022'
		# Will call the uninstaller but does it incompletely and messy. Keeping in case this ever gets better. Used Get-Uninstaller for MSIs below

		#Uninstall E-drawings
		Execute-MSI -Action Uninstall -Path '{08A73D4E-3FD0-4242-B08F-A41D8969C5B4}'
		#Uninstall CAM 2022
		Execute-MSI -Action Uninstall -Path '{46053718-2931-47EA-B678-6DF08370F2D4}'
		#Uninstall Flow SImulations 2022
		Execute-MSI -Action Uninstall -Path '{A9F14961-697D-455C-B48B-FCE9E22664A5}'
		#Uninstall File Utilities
		Execute-MSI -Action Uninstall -Path '{E3B4130E-6066-4613-918C-6EB5E7B68D8C}'
		#uninstall Solidworks 2022
		Execute-MSI -Action Uninstall -Path '{26EA0056-4BAD-4F9E-BDCE-A72E25C7D06D}'

		#Remove extra folders and data
		Remove-Folder -Path "$envProgramData\SOLIDWORKS"
		Remove-Folder -Path "$envSystemDrive\SOLIDWORKS Data"
		Remove-Folder -Path "$envProgramFiles\SOLIDWORKS Corp"



		# Removes Solidworks Installation Manager and entry from Add/Remove
		Remove-RegistryKey -Key 'HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\SolidWorks Installation Manager 20220-40301-1100-100' -Recurse
		Remove-Folder -Path 'C:\Windows\Solidworks'

		
		#>


		##*===============================================
		##* INSTALLATION
		##*===============================================
		[string]$installPhase = 'Installation'

		## Handle Zero-Config MSI Installations
		If ($useDefaultMsi) {
			[hashtable]$ExecuteDefaultMSISplat =  @{ Action = 'Install'; Path = $defaultMsiFile }; If ($defaultMstFile) { $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile) }
			Execute-MSI @ExecuteDefaultMSISplat; If ($defaultMspFiles) { $defaultMspFiles | ForEach-Object { Execute-MSI -Action 'Patch' -Path $_ } }
		}

		## <Perform Installation tasks here>
		$exitCode = Execute-Process -Path "\\vmwfs14.winad.msudenver.edu\lab\LabInstallers\Solidworks\2023SP2\startswinstall.exe" -Parameters "/install /now" -WindowStyle "Hidden" -PassThru
        If (($exitCode.ExitCode -ne "0") -and ($mainExitCode -ne "3010")) { $mainExitCode = $exitCode.ExitCode }


		## Restart explorer if it's closed
		$ProcessActive = Get-Process explorer -ErrorAction SilentlyContinue
        if(!$ProcessActive){
            Execute-ProcessAsUser -Path "$envSystemRoot\explorer.exe"
            Write-Log "Restarting Explorer"
        }
        Else{
            Write-Log "No restart of explorer needed"
        }

		##*===============================================
		##* POST-INSTALLATION
		##*===============================================
		[string]$installPhase = 'Post-Installation'

		## <Perform Post-Installation tasks here>

		## Display a message at the end of the install
		If (-not $useDefaultMsi) {}
	}
	ElseIf ($deploymentType -ieq 'Uninstall')
	{
		##*===============================================
		##* PRE-UNINSTALLATION
		##*===============================================
		[string]$installPhase = 'Pre-Uninstallation'

		## Show Welcome Message, close Internet Explorer with a 60 second countdown before automatically closing
		Show-InstallationWelcome -CloseApps 'sldProdMon,SLDWORKS,sldworks_fs' -silent

		## Show Progress Message (with the default message)
		Show-InstallationProgress

		## <Perform Pre-Uninstallation tasks here>


		##*===============================================
		##* UNINSTALLATION
		##*===============================================
		[string]$installPhase = 'Uninstallation'

		## Handle Zero-Config MSI Uninstallations
		If ($useDefaultMsi) {
			[hashtable]$ExecuteDefaultMSISplat =  @{ Action = 'Uninstall'; Path = $defaultMsiFile }; If ($defaultMstFile) { $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile) }
			Execute-MSI @ExecuteDefaultMSISplat
		}

		# <Perform Uninstallation tasks here>
		# Remove-MSIApplications -Name 'SolidWorks 2023'
		# Will call the uninstaller but does it incompletely and messy. Keeping in case this ever gets better. Used Get-Uninstaller for MSIs below

		#Uninstall E-drawings
		Execute-MSI -Action Uninstall -Path '{5DA7B824-6CD3-464E-A321-7A12A5AAC688}'
		#Uninstall CAM 2023
		Execute-MSI -Action Uninstall -Path '{6336104B-A756-43B6-9E4A-90A6F0B73709}'
		#Uninstall Flow SImulations 2023
		Execute-MSI -Action Uninstall -Path '{CA66BF32-7373-41D3-83E6-AEEB00F777E7}'
		#Uninstall File Utilities 2023
		Execute-MSI -Action Uninstall -Path '{27D1CA1A-717A-4A47-8680-9D35E57EDEB4}'
		#uninstall Solidworks 2023
		Execute-MSI -Action Uninstall -Path '{F24FAABB-0C72-4F06-9B55-DB08C884730C}'
		#uninstall CEF for SOLIDWORKS Applications
		Execute-MSI -Action Uninstall -Path '{93D5C716-DD70-4353-A1F7-AD013F1EE7AD}'

		#Remove extra folders and data
		Remove-Folder -Path "$envProgramData\SOLIDWORKS"
		Remove-Folder -Path "$envSystemDrive\SOLIDWORKS Data"
		Remove-Folder -Path "$envProgramFiles\SOLIDWORKS Corp"
		Remove-Folder -Path "$envProgramData\Microsoft\Windows\Start Menu\Programs\SOLIDWORKS Installation Manager"



		# Removes Solidworks Installation Manager and entry from Add/Remove
		Remove-RegistryKey -Key 'HKEY_LOCAL_MACHINE\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\SolidWorks Installation Manager 20230-40201-1100-100' -Recurse
		Remove-Folder -Path 'C:\Windows\Solidworks'

		##*===============================================
		##* POST-UNINSTALLATION
		##*===============================================
		[string]$installPhase = 'Post-Uninstallation'

		## <Perform Post-Uninstallation tasks here>


	}
	ElseIf ($deploymentType -ieq 'Repair')
	{
		##*===============================================
		##* PRE-REPAIR
		##*===============================================
		[string]$installPhase = 'Pre-Repair'

		## Show Progress Message (with the default message)
		Show-InstallationProgress

		## <Perform Pre-Repair tasks here>

		##*===============================================
		##* REPAIR
		##*===============================================
		[string]$installPhase = 'Repair'

		## Handle Zero-Config MSI Repairs
		If ($useDefaultMsi) {
			[hashtable]$ExecuteDefaultMSISplat =  @{ Action = 'Repair'; Path = $defaultMsiFile; }; If ($defaultMstFile) { $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile) }
			Execute-MSI @ExecuteDefaultMSISplat
		}
		# <Perform Repair tasks here>

		##*===============================================
		##* POST-REPAIR
		##*===============================================
		[string]$installPhase = 'Post-Repair'

		## <Perform Post-Repair tasks here>


    }
	##*===============================================
	##* END SCRIPT BODY
	##*===============================================

	## Call the Exit-Script function to perform final cleanup operations
	Exit-Script -ExitCode $mainExitCode
}
Catch {
	[int32]$mainExitCode = 60001
	[string]$mainErrorMessage = "$(Resolve-Error)"
	Write-Log -Message $mainErrorMessage -Severity 3 -Source $deployAppScriptFriendlyName
	Show-DialogBox -Text $mainErrorMessage -Icon 'Stop'
	Exit-Script -ExitCode $mainExitCode
}




# SIG # Begin signature block
# MIImVAYJKoZIhvcNAQcCoIImRTCCJkECAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCA6pGXLp7sZGrO/
# zoZCr9ZWinUP6Ti1NqyC13dUuiKhP6CCH8AwggVvMIIEV6ADAgECAhBI/JO0YFWU
# jTanyYqJ1pQWMA0GCSqGSIb3DQEBDAUAMHsxCzAJBgNVBAYTAkdCMRswGQYDVQQI
# DBJHcmVhdGVyIE1hbmNoZXN0ZXIxEDAOBgNVBAcMB1NhbGZvcmQxGjAYBgNVBAoM
# EUNvbW9kbyBDQSBMaW1pdGVkMSEwHwYDVQQDDBhBQUEgQ2VydGlmaWNhdGUgU2Vy
# dmljZXMwHhcNMjEwNTI1MDAwMDAwWhcNMjgxMjMxMjM1OTU5WjBWMQswCQYDVQQG
# EwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMS0wKwYDVQQDEyRTZWN0aWdv
# IFB1YmxpYyBDb2RlIFNpZ25pbmcgUm9vdCBSNDYwggIiMA0GCSqGSIb3DQEBAQUA
# A4ICDwAwggIKAoICAQCN55QSIgQkdC7/FiMCkoq2rjaFrEfUI5ErPtx94jGgUW+s
# hJHjUoq14pbe0IdjJImK/+8Skzt9u7aKvb0Ffyeba2XTpQxpsbxJOZrxbW6q5KCD
# J9qaDStQ6Utbs7hkNqR+Sj2pcaths3OzPAsM79szV+W+NDfjlxtd/R8SPYIDdub7
# P2bSlDFp+m2zNKzBenjcklDyZMeqLQSrw2rq4C+np9xu1+j/2iGrQL+57g2extme
# me/G3h+pDHazJyCh1rr9gOcB0u/rgimVcI3/uxXP/tEPNqIuTzKQdEZrRzUTdwUz
# T2MuuC3hv2WnBGsY2HH6zAjybYmZELGt2z4s5KoYsMYHAXVn3m3pY2MeNn9pib6q
# RT5uWl+PoVvLnTCGMOgDs0DGDQ84zWeoU4j6uDBl+m/H5x2xg3RpPqzEaDux5mcz
# mrYI4IAFSEDu9oJkRqj1c7AGlfJsZZ+/VVscnFcax3hGfHCqlBuCF6yH6bbJDoEc
# QNYWFyn8XJwYK+pF9e+91WdPKF4F7pBMeufG9ND8+s0+MkYTIDaKBOq3qgdGnA2T
# OglmmVhcKaO5DKYwODzQRjY1fJy67sPV+Qp2+n4FG0DKkjXp1XrRtX8ArqmQqsV/
# AZwQsRb8zG4Y3G9i/qZQp7h7uJ0VP/4gDHXIIloTlRmQAOka1cKG8eOO7F/05QID
# AQABo4IBEjCCAQ4wHwYDVR0jBBgwFoAUoBEKIz6W8Qfs4q8p74Klf9AwpLQwHQYD
# VR0OBBYEFDLrkpr/NZZILyhAQnAgNpFcF4XmMA4GA1UdDwEB/wQEAwIBhjAPBgNV
# HRMBAf8EBTADAQH/MBMGA1UdJQQMMAoGCCsGAQUFBwMDMBsGA1UdIAQUMBIwBgYE
# VR0gADAIBgZngQwBBAEwQwYDVR0fBDwwOjA4oDagNIYyaHR0cDovL2NybC5jb21v
# ZG9jYS5jb20vQUFBQ2VydGlmaWNhdGVTZXJ2aWNlcy5jcmwwNAYIKwYBBQUHAQEE
# KDAmMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5jb21vZG9jYS5jb20wDQYJKoZI
# hvcNAQEMBQADggEBABK/oe+LdJqYRLhpRrWrJAoMpIpnuDqBv0WKfVIHqI0fTiGF
# OaNrXi0ghr8QuK55O1PNtPvYRL4G2VxjZ9RAFodEhnIq1jIV9RKDwvnhXRFAZ/ZC
# J3LFI+ICOBpMIOLbAffNRk8monxmwFE2tokCVMf8WPtsAO7+mKYulaEMUykfb9gZ
# pk+e96wJ6l2CxouvgKe9gUhShDHaMuwV5KZMPWw5c9QLhTkg4IUaaOGnSDip0TYl
# d8GNGRbFiExmfS9jzpjoad+sPKhdnckcW67Y8y90z7h+9teDnRGWYpquRRPaf9xH
# +9/DUp/mBlXpnYzyOmJRvOwkDynUWICE5EV7WtgwggYaMIIEAqADAgECAhBiHW0M
# UgGeO5B5FSCJIRwKMA0GCSqGSIb3DQEBDAUAMFYxCzAJBgNVBAYTAkdCMRgwFgYD
# VQQKEw9TZWN0aWdvIExpbWl0ZWQxLTArBgNVBAMTJFNlY3RpZ28gUHVibGljIENv
# ZGUgU2lnbmluZyBSb290IFI0NjAeFw0yMTAzMjIwMDAwMDBaFw0zNjAzMjEyMzU5
# NTlaMFQxCzAJBgNVBAYTAkdCMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxKzAp
# BgNVBAMTIlNlY3RpZ28gUHVibGljIENvZGUgU2lnbmluZyBDQSBSMzYwggGiMA0G
# CSqGSIb3DQEBAQUAA4IBjwAwggGKAoIBgQCbK51T+jU/jmAGQ2rAz/V/9shTUxjI
# ztNsfvxYB5UXeWUzCxEeAEZGbEN4QMgCsJLZUKhWThj/yPqy0iSZhXkZ6Pg2A2NV
# DgFigOMYzB2OKhdqfWGVoYW3haT29PSTahYkwmMv0b/83nbeECbiMXhSOtbam+/3
# 6F09fy1tsB8je/RV0mIk8XL/tfCK6cPuYHE215wzrK0h1SWHTxPbPuYkRdkP05Zw
# mRmTnAO5/arnY83jeNzhP06ShdnRqtZlV59+8yv+KIhE5ILMqgOZYAENHNX9SJDm
# +qxp4VqpB3MV/h53yl41aHU5pledi9lCBbH9JeIkNFICiVHNkRmq4TpxtwfvjsUe
# dyz8rNyfQJy/aOs5b4s+ac7IH60B+Ja7TVM+EKv1WuTGwcLmoU3FpOFMbmPj8pz4
# 4MPZ1f9+YEQIQty/NQd/2yGgW+ufflcZ/ZE9o1M7a5Jnqf2i2/uMSWymR8r2oQBM
# dlyh2n5HirY4jKnFH/9gRvd+QOfdRrJZb1sCAwEAAaOCAWQwggFgMB8GA1UdIwQY
# MBaAFDLrkpr/NZZILyhAQnAgNpFcF4XmMB0GA1UdDgQWBBQPKssghyi47G9IritU
# pimqF6TNDDAOBgNVHQ8BAf8EBAMCAYYwEgYDVR0TAQH/BAgwBgEB/wIBADATBgNV
# HSUEDDAKBggrBgEFBQcDAzAbBgNVHSAEFDASMAYGBFUdIAAwCAYGZ4EMAQQBMEsG
# A1UdHwREMEIwQKA+oDyGOmh0dHA6Ly9jcmwuc2VjdGlnby5jb20vU2VjdGlnb1B1
# YmxpY0NvZGVTaWduaW5nUm9vdFI0Ni5jcmwwewYIKwYBBQUHAQEEbzBtMEYGCCsG
# AQUFBzAChjpodHRwOi8vY3J0LnNlY3RpZ28uY29tL1NlY3RpZ29QdWJsaWNDb2Rl
# U2lnbmluZ1Jvb3RSNDYucDdjMCMGCCsGAQUFBzABhhdodHRwOi8vb2NzcC5zZWN0
# aWdvLmNvbTANBgkqhkiG9w0BAQwFAAOCAgEABv+C4XdjNm57oRUgmxP/BP6YdURh
# w1aVcdGRP4Wh60BAscjW4HL9hcpkOTz5jUug2oeunbYAowbFC2AKK+cMcXIBD0Zd
# OaWTsyNyBBsMLHqafvIhrCymlaS98+QpoBCyKppP0OcxYEdU0hpsaqBBIZOtBajj
# cw5+w/KeFvPYfLF/ldYpmlG+vd0xqlqd099iChnyIMvY5HexjO2AmtsbpVn0OhNc
# WbWDRF/3sBp6fWXhz7DcML4iTAWS+MVXeNLj1lJziVKEoroGs9Mlizg0bUMbOalO
# hOfCipnx8CaLZeVme5yELg09Jlo8BMe80jO37PU8ejfkP9/uPak7VLwELKxAMcJs
# zkyeiaerlphwoKx1uHRzNyE6bxuSKcutisqmKL5OTunAvtONEoteSiabkPVSZ2z7
# 6mKnzAfZxCl/3dq3dUNw4rg3sTCggkHSRqTqlLMS7gjrhTqBmzu1L90Y1KWN/Y5J
# KdGvspbOrTfOXyXvmPL6E52z1NZJ6ctuMFBQZH3pwWvqURR8AgQdULUvrxjUYbHH
# j95Ejza63zdrEcxWLDX6xWls/GDnVNueKjWUH3fTv1Y8Wdho698YADR7TNx8X8z2
# Bev6SivBBOHY+uqiirZtg0y9ShQoPzmCcn63Syatatvx157YK9hlcPmVoa1oDE5/
# L9Uo2bC5a4CH2RwwggZCMIIEqqADAgECAhEApU3fcPvc8UxUgrjysXLKMTANBgkq
# hkiG9w0BAQwFADBUMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1p
# dGVkMSswKQYDVQQDEyJTZWN0aWdvIFB1YmxpYyBDb2RlIFNpZ25pbmcgQ0EgUjM2
# MB4XDTIxMDYwOTAwMDAwMFoXDTI0MDYwODIzNTk1OVowgZUxCzAJBgNVBAYTAlVT
# MREwDwYDVQQIDAhDb2xvcmFkbzEPMA0GA1UEBwwGRGVudmVyMTAwLgYDVQQKDCdN
# ZXRyb3BvbGl0YW4gU3RhdGUgVW5pdmVyc2l0eSBvZiBEZW52ZXIxMDAuBgNVBAMM
# J01ldHJvcG9saXRhbiBTdGF0ZSBVbml2ZXJzaXR5IG9mIERlbnZlcjCCAaIwDQYJ
# KoZIhvcNAQEBBQADggGPADCCAYoCggGBAKboC13rIRz9blQI2n+HkGKRao8qAg0x
# ItxGNohGKXOT1Ua7hDWG5+l2MBpddbQQfMSOyFT+AyisStRfFRb1TU1aSI8QxHJ1
# vkOq64AZKXIKuNxTEQv71RKyTgnjzduII4QqBhsIsrX4vN5PaFq/yKjJqKSsYQjF
# ej4Kx2fORXMFRHnqaAGW7qAwJvKcTUCzVn/1hq9dh6b3TxOd3t1x2L0Paz/4aF+J
# AhkNOF9Gc2B8heToRllTQOOSUdPz3wkW3y7u6zcJMEgxenniTP7fk348hXlrPBjy
# Z7qizCJ3wWH+QRqBqSheKZN/Olw6aYdqLAmbl9LZ3Z0/rvQMk/ADTHsY5jAXwARj
# xAlU+gnxj/6kysS6JDFP+0H7CD3fRlSBOWscPbg314zeGMx8eOLN81WWKu/79S3W
# HWAf84uxNnp2DcV/8aNsjXoaxfdQWXJp6s3V1wf5Jywv7nxcZgtS5+MJzHTv+Yc3
# hPUP7XjLpaAinHf8+rae6yP7OV6r3JZ39QIDAQABo4IByzCCAccwHwYDVR0jBBgw
# FoAUDyrLIIcouOxvSK4rVKYpqhekzQwwHQYDVR0OBBYEFMtdqsyLtKCxfncLB6Dk
# r4Az8FclMA4GA1UdDwEB/wQEAwIHgDAMBgNVHRMBAf8EAjAAMBMGA1UdJQQMMAoG
# CCsGAQUFBwMDMBEGCWCGSAGG+EIBAQQEAwIEEDBKBgNVHSAEQzBBMDUGDCsGAQQB
# sjEBAgEDAjAlMCMGCCsGAQUFBwIBFhdodHRwczovL3NlY3RpZ28uY29tL0NQUzAI
# BgZngQwBBAEwSQYDVR0fBEIwQDA+oDygOoY4aHR0cDovL2NybC5zZWN0aWdvLmNv
# bS9TZWN0aWdvUHVibGljQ29kZVNpZ25pbmdDQVIzNi5jcmwweQYIKwYBBQUHAQEE
# bTBrMEQGCCsGAQUFBzAChjhodHRwOi8vY3J0LnNlY3RpZ28uY29tL1NlY3RpZ29Q
# dWJsaWNDb2RlU2lnbmluZ0NBUjM2LmNydDAjBggrBgEFBQcwAYYXaHR0cDovL29j
# c3Auc2VjdGlnby5jb20wLQYDVR0RBCYwJIEiaXRzc3lzdGVtZW5naW5lZXJpbmdA
# bXN1ZGVudmVyLmVkdTANBgkqhkiG9w0BAQwFAAOCAYEAf8UAUe7L6IftWT8u5nDy
# eSlAgGxBzj4Dd3xgjRwkshSH7H5TvyTadkZlBBooTL390IG1X1uvLHmOC23qGI0Y
# ytYLCfNcKpq1Jjo8V0Jc9e1RwHGH/z653cJ4TsCYYdGTgtwz1J1OZHHVeMwr0p6y
# 3g7t0ERRuBClq1vnixURJyWRwg7mlSjBriRpv2AKY8xwSB3JMcDF9+YsRYCShih+
# hLcPp4YygkaHjlVhc5K/iKsoS1j7CT4qbjVl077CmVysO8KMDSTATMfOaYFngaxF
# vPfOcqNxCu8n1IMIFnMndoiWe/St3tDdwgSdQQqBxZ24KZZGDqa9j+jlvcO7AviT
# 258+icvZibXngUBM1aTePvMnW91uTJlwyl58K1W2CDnXVps8TZUMXQq8uD9Yn4VA
# 1MDNkfN5meHBUmmiI8ZMHBr2trzM94U/EpTCVK+HuSlOB0oTVC09tMqrcoK3UJXN
# dNc+j+IKHek+dzUcwi4VgmJG+dgrgSXPVPc2s0+AvTfzMIIG7DCCBNSgAwIBAgIQ
# MA9vrN1mmHR8qUY2p3gtuTANBgkqhkiG9w0BAQwFADCBiDELMAkGA1UEBhMCVVMx
# EzARBgNVBAgTCk5ldyBKZXJzZXkxFDASBgNVBAcTC0plcnNleSBDaXR5MR4wHAYD
# VQQKExVUaGUgVVNFUlRSVVNUIE5ldHdvcmsxLjAsBgNVBAMTJVVTRVJUcnVzdCBS
# U0EgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkwHhcNMTkwNTAyMDAwMDAwWhcNMzgw
# MTE4MjM1OTU5WjB9MQswCQYDVQQGEwJHQjEbMBkGA1UECBMSR3JlYXRlciBNYW5j
# aGVzdGVyMRAwDgYDVQQHEwdTYWxmb3JkMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0
# ZWQxJTAjBgNVBAMTHFNlY3RpZ28gUlNBIFRpbWUgU3RhbXBpbmcgQ0EwggIiMA0G
# CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDIGwGv2Sx+iJl9AZg/IJC9nIAhVJO5
# z6A+U++zWsB21hoEpc5Hg7XrxMxJNMvzRWW5+adkFiYJ+9UyUnkuyWPCE5u2hj8B
# BZJmbyGr1XEQeYf0RirNxFrJ29ddSU1yVg/cyeNTmDoqHvzOWEnTv/M5u7mkI0Ks
# 0BXDf56iXNc48RaycNOjxN+zxXKsLgp3/A2UUrf8H5VzJD0BKLwPDU+zkQGObp0n
# dVXRFzs0IXuXAZSvf4DP0REKV4TJf1bgvUacgr6Unb+0ILBgfrhN9Q0/29DqhYyK
# VnHRLZRMyIw80xSinL0m/9NTIMdgaZtYClT0Bef9Maz5yIUXx7gpGaQpL0bj3duR
# X58/Nj4OMGcrRrc1r5a+2kxgzKi7nw0U1BjEMJh0giHPYla1IXMSHv2qyghYh3ek
# FesZVf/QOVQtJu5FGjpvzdeE8NfwKMVPZIMC1Pvi3vG8Aij0bdonigbSlofe6GsO
# 8Ft96XZpkyAcSpcsdxkrk5WYnJee647BeFbGRCXfBhKaBi2fA179g6JTZ8qx+o2h
# ZMmIklnLqEbAyfKm/31X2xJ2+opBJNQb/HKlFKLUrUMcpEmLQTkUAx4p+hulIq6l
# w02C0I3aa7fb9xhAV3PwcaP7Sn1FNsH3jYL6uckNU4B9+rY5WDLvbxhQiddPnTO9
# GrWdod6VQXqngwIDAQABo4IBWjCCAVYwHwYDVR0jBBgwFoAUU3m/WqorSs9UgOHY
# m8Cd8rIDZsswHQYDVR0OBBYEFBqh+GEZIA/DQXdFKI7RNV8GEgRVMA4GA1UdDwEB
# /wQEAwIBhjASBgNVHRMBAf8ECDAGAQH/AgEAMBMGA1UdJQQMMAoGCCsGAQUFBwMI
# MBEGA1UdIAQKMAgwBgYEVR0gADBQBgNVHR8ESTBHMEWgQ6BBhj9odHRwOi8vY3Js
# LnVzZXJ0cnVzdC5jb20vVVNFUlRydXN0UlNBQ2VydGlmaWNhdGlvbkF1dGhvcml0
# eS5jcmwwdgYIKwYBBQUHAQEEajBoMD8GCCsGAQUFBzAChjNodHRwOi8vY3J0LnVz
# ZXJ0cnVzdC5jb20vVVNFUlRydXN0UlNBQWRkVHJ1c3RDQS5jcnQwJQYIKwYBBQUH
# MAGGGWh0dHA6Ly9vY3NwLnVzZXJ0cnVzdC5jb20wDQYJKoZIhvcNAQEMBQADggIB
# AG1UgaUzXRbhtVOBkXXfA3oyCy0lhBGysNsqfSoF9bw7J/RaoLlJWZApbGHLtVDb
# 4n35nwDvQMOt0+LkVvlYQc/xQuUQff+wdB+PxlwJ+TNe6qAcJlhc87QRD9XVw+K8
# 1Vh4v0h24URnbY+wQxAPjeT5OGK/EwHFhaNMxcyyUzCVpNb0llYIuM1cfwGWvnJS
# ajtCN3wWeDmTk5SbsdyybUFtZ83Jb5A9f0VywRsj1sJVhGbks8VmBvbz1kteraMr
# Qoohkv6ob1olcGKBc2NeoLvY3NdK0z2vgwY4Eh0khy3k/ALWPncEvAQ2ted3y5wu
# jSMYuaPCRx3wXdahc1cFaJqnyTdlHb7qvNhCg0MFpYumCf/RoZSmTqo9CfUFbLfS
# ZFrYKiLCS53xOV5M3kg9mzSWmglfjv33sVKRzj+J9hyhtal1H3G/W0NdZT1QgW6r
# 8NDT/LKzH7aZlib0PHmLXGTMze4nmuWgwAxyh8FuTVrTHurwROYybxzrF06Uw3hl
# IDsPQaof6aFBnf6xuKBlKjTg3qj5PObBMLvAoGMs/FwWAKjQxH/qEZ0eBsambTJd
# tDgJK0kHqv3sMNrxpy/Pt/360KOE2See+wFmd7lWEOEgbsausfm2usg1XTN2jvF8
# IAwqd661ogKGuinutFoAsYyr4/kKyVRd1LlqdJ69SK6YMIIG9TCCBN2gAwIBAgIQ
# OUwl4XygbSeoZeI72R0i1DANBgkqhkiG9w0BAQwFADB9MQswCQYDVQQGEwJHQjEb
# MBkGA1UECBMSR3JlYXRlciBNYW5jaGVzdGVyMRAwDgYDVQQHEwdTYWxmb3JkMRgw
# FgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxJTAjBgNVBAMTHFNlY3RpZ28gUlNBIFRp
# bWUgU3RhbXBpbmcgQ0EwHhcNMjMwNTAzMDAwMDAwWhcNMzQwODAyMjM1OTU5WjBq
# MQswCQYDVQQGEwJHQjETMBEGA1UECBMKTWFuY2hlc3RlcjEYMBYGA1UEChMPU2Vj
# dGlnbyBMaW1pdGVkMSwwKgYDVQQDDCNTZWN0aWdvIFJTQSBUaW1lIFN0YW1waW5n
# IFNpZ25lciAjNDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAKSTKFJL
# zyeHdqQpHJk4wOcO1NEc7GjLAWTkis13sHFlgryf/Iu7u5WY+yURjlqICWYRFFiy
# uiJb5vYy8V0twHqiDuDgVmTtoeWBIHIgZEFsx8MI+vN9Xe8hmsJ+1yzDuhGYHvzT
# IAhCs1+/f4hYMqsws9iMepZKGRNcrPznq+kcFi6wsDiVSs+FUKtnAyWhuzjpD2+p
# WpqRKBM1uR/zPeEkyGuxmegN77tN5T2MVAOR0Pwtz1UzOHoJHAfRIuBjhqe+/dKD
# cxIUm5pMCUa9NLzhS1B7cuBb/Rm7HzxqGXtuuy1EKr48TMysigSTxleGoHM2K4GX
# +hubfoiH2FJ5if5udzfXu1Cf+hglTxPyXnypsSBaKaujQod34PRMAkjdWKVTpqOg
# 7RmWZRUpxe0zMCXmloOBmvZgZpBYB4DNQnWs+7SR0MXdAUBqtqgQ7vaNereeda/T
# pUsYoQyfV7BeJUeRdM11EtGcb+ReDZvsdSbu/tP1ki9ShejaRFEqoswAyodmQ6Mb
# AO+itZadYq0nC/IbSsnDlEI3iCCEqIeuw7ojcnv4VO/4ayewhfWnQ4XYKzl021p3
# AtGk+vXNnD3MH65R0Hts2B0tEUJTcXTC5TWqLVIS2SXP8NPQkUMS1zJ9mGzjd0HI
# /x8kVO9urcY+VXvxXIc6ZPFgSwVP77kv7AkTAgMBAAGjggGCMIIBfjAfBgNVHSME
# GDAWgBQaofhhGSAPw0F3RSiO0TVfBhIEVTAdBgNVHQ4EFgQUAw8xyJEqk71j89Fd
# TaQ0D9KVARgwDgYDVR0PAQH/BAQDAgbAMAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/
# BAwwCgYIKwYBBQUHAwgwSgYDVR0gBEMwQTA1BgwrBgEEAbIxAQIBAwgwJTAjBggr
# BgEFBQcCARYXaHR0cHM6Ly9zZWN0aWdvLmNvbS9DUFMwCAYGZ4EMAQQCMEQGA1Ud
# HwQ9MDswOaA3oDWGM2h0dHA6Ly9jcmwuc2VjdGlnby5jb20vU2VjdGlnb1JTQVRp
# bWVTdGFtcGluZ0NBLmNybDB0BggrBgEFBQcBAQRoMGYwPwYIKwYBBQUHMAKGM2h0
# dHA6Ly9jcnQuc2VjdGlnby5jb20vU2VjdGlnb1JTQVRpbWVTdGFtcGluZ0NBLmNy
# dDAjBggrBgEFBQcwAYYXaHR0cDovL29jc3Auc2VjdGlnby5jb20wDQYJKoZIhvcN
# AQEMBQADggIBAEybZVj64HnP7xXDMm3eM5Hrd1ji673LSjx13n6UbcMixwSV32Vp
# YRMM9gye9YkgXsGHxwMkysel8Cbf+PgxZQ3g621RV6aMhFIIRhwqwt7y2opF8773
# 9i7Efu347Wi/elZI6WHlmjl3vL66kWSIdf9dhRY0J9Ipy//tLdr/vpMM7G2iDczD
# 8W69IZEaIwBSrZfUYngqhHmo1z2sIY9wwyR5OpfxDaOjW1PYqwC6WPs1gE9fKHFs
# GV7Cg3KQruDG2PKZ++q0kmV8B3w1RB2tWBhrYvvebMQKqWzTIUZw3C+NdUwjwkHQ
# epY7w0vdzZImdHZcN6CaJJ5OX07Tjw/lE09ZRGVLQ2TPSPhnZ7lNv8wNsTow0KE9
# SK16ZeTs3+AB8LMqSjmswaT5qX010DJAoLEZKhghssh9BXEaSyc2quCYHIN158d+
# S4RDzUP7kJd2KhKsQMFwW5kKQPqAbZRhe8huuchnZyRcUI0BIN4H9wHU+C4RzZ2D
# 5fjKJRxEPSflsIZHKgsbhHZ9e2hPjbf3E7TtoC3ucw/ZELqdmSx813UfjxDElOZ+
# JOWVSoiMJ9aFZh35rmR2kehI/shVCu0pwx/eOKbAFPsyPfipg2I2yMO+AIccq/pK
# QhyJA9z1XHxw2V14Tu6fXiDmCWp8KwijSPUV/ARP380hHHrl9Y4a1LlAMYIF6jCC
# BeYCAQEwaTBUMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVk
# MSswKQYDVQQDEyJTZWN0aWdvIFB1YmxpYyBDb2RlIFNpZ25pbmcgQ0EgUjM2AhEA
# pU3fcPvc8UxUgrjysXLKMTANBglghkgBZQMEAgEFAKCBhDAYBgorBgEEAYI3AgEM
# MQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEEMBwGCisGAQQB
# gjcCAQsxDjAMBgorBgEEAYI3AgEVMC8GCSqGSIb3DQEJBDEiBCARhMTVzlAkr/mL
# ciwCRn+fL4DLm737DmRm4+FYkJbnnjANBgkqhkiG9w0BAQEFAASCAYBEJHcdSbG3
# 47lbsuZyNEbJt2keDxzUVDRrSv5d65ZCGDP6XKBFb/NyPWWy2ii9iG9fmqm/zy3C
# O372sPlvKtLdLdRaE5oDF32mEI4CEb1pbA7/to5Nh90paUwCrOfuAmvERg04Mx3J
# KcP5oc4vtZfscbfgj4AXU8x3aOqzvMex9bTmgtRKbTGHGdsMtgiyM24AEZceTtol
# m7kYLoElJ+j/kubl/hykIVCA2D0EPhbTs+VCsqoPLOf+pQhSd9TGQHEvaDlq/EhM
# 2DeZm7S5DMvrRXLh0HeonjI6VDlixfO7+KHA8EYouZuTIKe/cw5A7sgiOqwvZiJ3
# 1Y3mgENhImeXYwt6jfV0oR0JxxqVX/imdU/NELyA0viOd4a3mKD8Mhifo+khjzvl
# tg/rFPUFqkuAt6g8irONP4YTl52BJK+w+oYlwvQgKWsnCz5h+DRS9DhwAJKtl7og
# tOMHntkjZICkPdSHvy9HSK7/diyqY/NtR4I7lh89veEFn2llJOytbkOhggNLMIID
# RwYJKoZIhvcNAQkGMYIDODCCAzQCAQEwgZEwfTELMAkGA1UEBhMCR0IxGzAZBgNV
# BAgTEkdyZWF0ZXIgTWFuY2hlc3RlcjEQMA4GA1UEBxMHU2FsZm9yZDEYMBYGA1UE
# ChMPU2VjdGlnbyBMaW1pdGVkMSUwIwYDVQQDExxTZWN0aWdvIFJTQSBUaW1lIFN0
# YW1waW5nIENBAhA5TCXhfKBtJ6hl4jvZHSLUMA0GCWCGSAFlAwQCAgUAoHkwGAYJ
# KoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcNMjMwNzA1MTYz
# MDIxWjA/BgkqhkiG9w0BCQQxMgQwMJF2MEiRdcpxPspgrqjnEu1J5TT/JybMOexh
# RP5dCWFHTS+F+KW3+Yyl9aQBBn2TMA0GCSqGSIb3DQEBAQUABIICAKA/bM6nsYUL
# GXCp8hEdFQ5v/Wxufpmo27Ti/k/Wk6gGyVWP9js53+qMVdSUGVrTTttQF1frWn+c
# b60ryKCp7l/Pt4i6KNgqfN+C4+pAaJXD/dZWQ/5rLvIiSGEyzrlZi60fRkmSaWXT
# d4Kt7XSwm1sHge1tJdRCRwjsf/PJy8VhnJ+gsST9b4vLeBxQX8Xes2/2TCSANZBs
# VHNJUeEKsd0rLCzG8WYCRZl+swHF1r1CPB+p4xEp19p1xJY4HQE1USUPaKyQ3qGQ
# sJXyEAXHLoy3L4Uygr8A0bFv5Zm/slZ73b3jvrvcz/o+T5mtvTeSl6nHSyCsUebE
# Dis5KzIBOJrxvgtmwp2sJZdAdWe986YOByMDxKKeKF2bnYWfChFSddrBUtjmjGlv
# Nfak1PpMuIpsamLJSWgoY3P9/AAGF132wKl3+Z33M9NG52C4NQc4FCCZureGbLlV
# VBU2mO3aFNdfJGy1X1HD6yfC//mPShl8v2WsdivhRO20ttQ79UV50tOlyPwlq7cH
# OpiCIHgSbk5vVx24qzUzF7iqOqAiM/NdW09/v2lWOfVih3A7b5d8/Sxvk13Kaz4c
# K6sITMiL2bgKOyahVvx+ZS5zaog2rjDFLbk/52o9h5HvkYO8wSLyH2cwrYAVwpiK
# Pk0DksBbipzaoUvyo0zYewSfyO1e0IFU
# SIG # End signature block
