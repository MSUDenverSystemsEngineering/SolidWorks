## Define variables
$fileShare = New-PSSession -ComputerName $Env:serverName

$stagingDir = $Env:stagingDirectory
$productionDir = $Env:productionDirectory
$cert = (Get-ChildItem Cert:\LocalMachine\My -CodeSigningCert)

$initParams = @{}
## Uncomment the next line for debugging
## $initParams.Add("Verbose", $true)

## Set application properties
$appName = $Env:APPVEYOR_PROJECT_NAME
$appName = $appName -replace '-',' ' -replace '_',' '
$install = "Deploy-Application.exe -DeploymentType `"Install`" -AllowRebootPassThru"
$uninstall = "Deploy-Application.exe -DeploymentType `"Uninstall`" -AllowRebootPassThru"

## Determine the app's author
switch ($Env:APPVEYOR_REPO_COMMIT_AUTHOR) {
  $Env:jordanGitHub { $author = $Env:jordan }
  $Env:quanGitHub { $author = $Env:quan }
  $Env:steveGitHub { $author = $Env:steve }
  $Env:truongGitHub { $author = $Env:truong }
}

## Remove unneeded files from the repository before uploading to the file share
Write-Output "Cleaning up Git and CI files..."
Remove-Item -Path "$Env:APPLICATION_PATH\appveyor.yml"
Remove-Item -Path "$Env:APPLICATION_PATH\deploy.ps1"
Remove-Item -Path "$Env:APPLICATION_PATH\TestsResults.xml"
Remove-Item -Path "$Env:APPLICATION_PATH\.DS_Store" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$Env:APPLICATION_PATH\.gitignore" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$Env:APPLICATION_PATH\.gitattributes" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$Env:APPLICATION_PATH\Tests" -Recurse
Remove-Item -Path "$Env:APPLICATION_PATH\.git" -Recurse -Force

## Sign the PowerShell file to allow running the script directly with a RemoteSigned execution policy
Set-AuthenticodeSignature "$Env:APPLICATION_PATH\Deploy-Application.ps1" $cert -HashAlgorithm SHA256 -TimestampServer "http://timestamp.globalsign.com/scripts/timestamp.dll"
Set-AuthenticodeSignature "$Env:APPLICATION_PATH\AppDeployToolkit\AppDeployToolkitExtensions.ps1" $cert -HashAlgorithm SHA256 -TimestampServer "http://timestamp.globalsign.com/scripts/timestamp.dll"
Set-AuthenticodeSignature "$Env:APPLICATION_PATH\AppDeployToolkit\AppDeployToolkitHelp.ps1" $cert -HashAlgorithm SHA256 -TimestampServer "http://timestamp.globalsign.com/scripts/timestamp.dll"
Set-AuthenticodeSignature "$Env:APPLICATION_PATH\AppDeployToolkit\AppDeployToolkitMain.ps1" $cert -HashAlgorithm SHA256 -TimestampServer "http://timestamp.globalsign.com/scripts/timestamp.dll"

$contentLocation = "$Env:stagingContentLocation\$appName"

## Remove previous staging toolkit files if detected, except for Files and SupportFiles
Invoke-Command -Session $fileShare -ScriptBlock {
  If (Test-Path -Path "$Using:stagingDir\$Using:appName" -PathType Container) {
    Write-Output "Removing staging PowerShell App Deployment Toolkit..."
    Remove-Item -Path "$Using:stagingDir\$Using:appName\*.*" -Force | Where-Object { ! $_.PSIsContainer }
    Remove-Item -Path "$Using:stagingDir\$Using:appName\AppDeployToolkit" -Force -Recurse | Where-Object { $_.PSIsContainer }
  } Else {
    New-Item -Path $Using:stagingDir -Name $Using:appName -ItemType "directory"
  }
}

## Upload the repository to the staging directory, overwriting any remaining files or support files
Copy-Item -Path "$Env:APPLICATION_PATH\*" -Destination "$stagingDir\$appName\" -ToSession $fileShare -Force -Recurse

## Set the application name as we want it to appear in Configuration Manager
$appName = "Staging - $appName"

## Import the ConfigurationManager.psd1 module
If ((Get-Module ConfigurationManager) -eq $null) {
  Import-Module "$($Env:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams
}

## Connect to the site's drive if it is not already present
If ((Get-PSDrive -Name $Env:siteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
  New-PSDrive -Name $Env:siteCode -PSProvider CMSite -Root $Env:siteServer @initParams
}

## Set the active PSDrive to the ConfigMgr site code
Set-Location "$($Env:siteCode):\" @initParams

## Create the ConfigMgr application (if if doesn't exist) in the format "Staging - GitHub project name"
## This also adds a link to the GitHub repository in the Administrator Comments field for reference and checks the box next to "Allow this application to be installed from the Install Application task sequence action without being deployed"
## Reference: https://docs.microsoft.com/en-us/powershell/module/configurationmanager/new-cmapplication
If ((Get-CMApplication -Name $appName -ErrorAction SilentlyContinue) -or (Get-CMApplication -Name "Staging - $Env:APPVEYOR_PROJECT_NAME" -ErrorAction SilentlyContinue)) {
  ## Rename an existing Staging application if detected
  If (Get-CMApplication -Name "Staging - $Env:APPVEYOR_PROJECT_NAME" -ErrorAction SilentlyContinue) {
    Get-CMApplication -Name "Staging - $Env:APPVEYOR_PROJECT_NAME" | Set-CMApplication -NewName $appName
  }
  ## Clear any existing owners and support contacts
  Get-CMApplication -Name $appName | Set-CMApplication -ClearOwner -ClearSupportContact
} Else {
  New-CMApplication -Name $appName
}

Get-CMApplication -Name $appName | Set-CMApplication -Description "Repository: https://github.com/$Env:APPVEYOR_REPO_NAME" -ReleaseDate $(Get-Date -Format d)  -Owner $author -SupportContact 'System Engineers' -AutoInstall $True

## Create a new script deployment type with standard settings for PowerShell App Deployment Toolkit
## You'll need to manually update the deployment type's detection method to find the software, make any other needed customizations to the application and deployment type, then distribute your content when ready.
## Reference: https://docs.microsoft.com/en-us/powershell/module/configurationmanager/add-cmscriptdeploymenttype
Get-CMApplication -Name $appName | Add-CMScriptDeploymentType -DeploymentTypeName "$appName $Env:APPVEYOR_BUILD_VERSION" -InstallCommand $install -ScriptLanguage "PowerShell" -ScriptText "Update this application's detection method to accurately locate the application." -ContentLocation $contentLocation -InstallationBehaviorType "InstallForSystem" -LogonRequirementType "WhetherOrNotUserLoggedOn" -MaximumRuntimeMins 120 -UninstallCommand $uninstall -UserInteractionMode "Normal" -Comment "Commit: https://github.com/$Env:APPVEYOR_REPO_NAME/commit/$Env:APPVEYOR_REPO_COMMIT" -ContentFallback -EnableBranchCache -SlowNetworkDeploymentMode 'Download'

# SIG # Begin signature block
# MIIfagYJKoZIhvcNAQcCoIIfWzCCH1cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCOgxhm9UH7zmyG
# vhQ8N0Z5PaF0a0a84cT8hE2HxeaGNKCCGdcwggQUMIIC/KADAgECAgsEAAAAAAEv
# TuFS1zANBgkqhkiG9w0BAQUFADBXMQswCQYDVQQGEwJCRTEZMBcGA1UEChMQR2xv
# YmFsU2lnbiBudi1zYTEQMA4GA1UECxMHUm9vdCBDQTEbMBkGA1UEAxMSR2xvYmFs
# U2lnbiBSb290IENBMB4XDTExMDQxMzEwMDAwMFoXDTI4MDEyODEyMDAwMFowUjEL
# MAkGA1UEBhMCQkUxGTAXBgNVBAoTEEdsb2JhbFNpZ24gbnYtc2ExKDAmBgNVBAMT
# H0dsb2JhbFNpZ24gVGltZXN0YW1waW5nIENBIC0gRzIwggEiMA0GCSqGSIb3DQEB
# AQUAA4IBDwAwggEKAoIBAQCU72X4tVefoFMNNAbrCR+3Rxhqy/Bb5P8npTTR94ka
# v56xzRJBbmbUgaCFi2RaRi+ZoI13seK8XN0i12pn0LvoynTei08NsFLlkFvrRw7x
# 55+cC5BlPheWMEVybTmhFzbKuaCMG08IGfaBMa1hFqRi5rRAnsP8+5X2+7UulYGY
# 4O/F69gCWXh396rjUmtQkSnF/PfNk2XSYGEi8gb7Mt0WUfoO/Yow8BcJp7vzBK6r
# kOds33qp9O/EYidfb5ltOHSqEYva38cUTOmFsuzCfUomj+dWuqbgz5JTgHT0A+xo
# smC8hCAAgxuh7rR0BcEpjmLQR7H68FPMGPkuO/lwfrQlAgMBAAGjgeUwgeIwDgYD
# VR0PAQH/BAQDAgEGMBIGA1UdEwEB/wQIMAYBAf8CAQAwHQYDVR0OBBYEFEbYPv/c
# 477/g+b0hZuw3WrWFKnBMEcGA1UdIARAMD4wPAYEVR0gADA0MDIGCCsGAQUFBwIB
# FiZodHRwczovL3d3dy5nbG9iYWxzaWduLmNvbS9yZXBvc2l0b3J5LzAzBgNVHR8E
# LDAqMCigJqAkhiJodHRwOi8vY3JsLmdsb2JhbHNpZ24ubmV0L3Jvb3QuY3JsMB8G
# A1UdIwQYMBaAFGB7ZhpFDZfKiVAvfQTNNKj//P1LMA0GCSqGSIb3DQEBBQUAA4IB
# AQBOXlaQHka02Ukx87sXOSgbwhbd/UHcCQUEm2+yoprWmS5AmQBVteo/pSB204Y0
# 1BfMVTrHgu7vqLq82AafFVDfzRZ7UjoC1xka/a/weFzgS8UY3zokHtqsuKlYBAIH
# MNuwEl7+Mb7wBEj08HD4Ol5Wg889+w289MXtl5251NulJ4TjOJuLpzWGRCCkO22k
# aguhg/0o69rvKPbMiF37CjsAq+Ah6+IvNWwPjjRFl+ui95kzNX7Lmoq7RU3nP5/C
# 2Yr6ZbJux35l/+iS4SwxovewJzZIjyZvO+5Ndh95w+V/ljW8LQ7MAbCOf/9RgICn
# ktSzREZkjIdPFmMHMUtjsN/zMIIEnzCCA4egAwIBAgISESHWmadklz7x+EJ+6RnM
# U0EUMA0GCSqGSIb3DQEBBQUAMFIxCzAJBgNVBAYTAkJFMRkwFwYDVQQKExBHbG9i
# YWxTaWduIG52LXNhMSgwJgYDVQQDEx9HbG9iYWxTaWduIFRpbWVzdGFtcGluZyBD
# QSAtIEcyMB4XDTE2MDUyNDAwMDAwMFoXDTI3MDYyNDAwMDAwMFowYDELMAkGA1UE
# BhMCU0cxHzAdBgNVBAoTFkdNTyBHbG9iYWxTaWduIFB0ZSBMdGQxMDAuBgNVBAMT
# J0dsb2JhbFNpZ24gVFNBIGZvciBNUyBBdXRoZW50aWNvZGUgLSBHMjCCASIwDQYJ
# KoZIhvcNAQEBBQADggEPADCCAQoCggEBALAXrqLTtgQwVh5YD7HtVaTWVMvY9nM6
# 7F1eqyX9NqX6hMNhQMVGtVlSO0KiLl8TYhCpW+Zz1pIlsX0j4wazhzoOQ/DXAIlT
# ohExUihuXUByPPIJd6dJkpfUbJCgdqf9uNyznfIHYCxPWJgAa9MVVOD63f+ALF8Y
# ppj/1KvsoUVZsi5vYl3g2Rmsi1ecqCYr2RelENJHCBpwLDOLf2iAKrWhXWvdjQIC
# KQOqfDe7uylOPVOTs6b6j9JYkxVMuS2rgKOjJfuv9whksHpED1wQ119hN6pOa9PS
# UyWdgnP6LPlysKkZOSpQ+qnQPDrK6Fvv9V9R9PkK2Zc13mqF5iMEQq8CAwEAAaOC
# AV8wggFbMA4GA1UdDwEB/wQEAwIHgDBMBgNVHSAERTBDMEEGCSsGAQQBoDIBHjA0
# MDIGCCsGAQUFBwIBFiZodHRwczovL3d3dy5nbG9iYWxzaWduLmNvbS9yZXBvc2l0
# b3J5LzAJBgNVHRMEAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMEIGA1UdHwQ7
# MDkwN6A1oDOGMWh0dHA6Ly9jcmwuZ2xvYmFsc2lnbi5jb20vZ3MvZ3N0aW1lc3Rh
# bXBpbmdnMi5jcmwwVAYIKwYBBQUHAQEESDBGMEQGCCsGAQUFBzAChjhodHRwOi8v
# c2VjdXJlLmdsb2JhbHNpZ24uY29tL2NhY2VydC9nc3RpbWVzdGFtcGluZ2cyLmNy
# dDAdBgNVHQ4EFgQU1KKESjhaGH+6TzBQvZ3VeofWCfcwHwYDVR0jBBgwFoAURtg+
# /9zjvv+D5vSFm7DdatYUqcEwDQYJKoZIhvcNAQEFBQADggEBAI+pGpFtBKY3IA6D
# lt4j02tuH27dZD1oISK1+Ec2aY7hpUXHJKIitykJzFRarsa8zWOOsz1QSOW0zK7N
# ko2eKIsTShGqvaPv07I2/LShcr9tl2N5jES8cC9+87zdglOrGvbr+hyXvLY3nKQc
# MLyrvC1HNt+SIAPoccZY9nUFmjTwC1lagkQ0qoDkL4T2R12WybbKyp23prrkUNPU
# N7i6IA7Q05IqW8RZu6Ft2zzORJ3BOCqt4429zQl3GhC+ZwoCNmSIubMbJu7nnmDE
# Rqi8YTNsz065nLlq8J83/rU9T5rTTf/eII5Ol6b9nwm8TcoYdsmwTYVQ8oDSHQb1
# WAQHsRgwggV3MIIEX6ADAgECAhAT6ihwW/Ts7Qw2YwmAYUM2MA0GCSqGSIb3DQEB
# DAUAMG8xCzAJBgNVBAYTAlNFMRQwEgYDVQQKEwtBZGRUcnVzdCBBQjEmMCQGA1UE
# CxMdQWRkVHJ1c3QgRXh0ZXJuYWwgVFRQIE5ldHdvcmsxIjAgBgNVBAMTGUFkZFRy
# dXN0IEV4dGVybmFsIENBIFJvb3QwHhcNMDAwNTMwMTA0ODM4WhcNMjAwNTMwMTA0
# ODM4WjCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCk5ldyBKZXJzZXkxFDASBgNV
# BAcTC0plcnNleSBDaXR5MR4wHAYDVQQKExVUaGUgVVNFUlRSVVNUIE5ldHdvcmsx
# LjAsBgNVBAMTJVVTRVJUcnVzdCBSU0EgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkw
# ggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCAEmUXNg7D2wiz0KxXDXbt
# zSfTTK1Qg2HiqiBNCS1kCdzOiZ/MPans9s/B3PHTsdZ7NygRK0faOca8Ohm0X6a9
# fZ2jY0K2dvKpOyuR+OJv0OwWIJAJPuLodMkYtJHUYmTbf6MG8YgYapAiPLz+E/CH
# FHv25B+O1ORRxhFnRghRy4YUVD+8M/5+bJz/Fp0YvVGONaanZshyZ9shZrHUm3gD
# wFA66Mzw3LyeTP6vBZY1H1dat//O+T23LLb2VN3I5xI6Ta5MirdcmrS3ID3KfyI0
# rn47aGYBROcBTkZTmzNg95S+UzeQc0PzMsNT79uq/nROacdrjGCT3sTHDN/hMq7M
# kztReJVni+49Vv4M0GkPGw/zJSZrM233bkf6c0Plfg6lZrEpfDKEY1WJxA3Bk1Qw
# GROs0303p+tdOmw1XNtB1xLaqUkL39iAigmTYo61Zs8liM2EuLE/pDkP2QKe6xJM
# lXzzawWpXhaDzLhn4ugTncxbgtNMs+1b/97lc6wjOy0AvzVVdAlJ2ElYGn+SNuZR
# kg7zJn0cTRe8yexDJtC/QV9AqURE9JnnV4eeUB9XVKg+/XRjL7FQZQnmWEIuQxpM
# tPAlR1n6BB6T1CZGSlCBst6+eLf8ZxXhyVeEHg9j1uliutZfVS7qXMYoCAQlObgO
# K6nyTJccBz8NUvXt7y+CDwIDAQABo4H0MIHxMB8GA1UdIwQYMBaAFK29mHo0tCb3
# +sQmVO8DveAky1QaMB0GA1UdDgQWBBRTeb9aqitKz1SA4dibwJ3ysgNmyzAOBgNV
# HQ8BAf8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zARBgNVHSAECjAIMAYGBFUdIAAw
# RAYDVR0fBD0wOzA5oDegNYYzaHR0cDovL2NybC51c2VydHJ1c3QuY29tL0FkZFRy
# dXN0RXh0ZXJuYWxDQVJvb3QuY3JsMDUGCCsGAQUFBwEBBCkwJzAlBggrBgEFBQcw
# AYYZaHR0cDovL29jc3AudXNlcnRydXN0LmNvbTANBgkqhkiG9w0BAQwFAAOCAQEA
# k2X2N4OVD17Dghwf1nfnPIrAqgnw6Qsm8eDCanWhx3nJuVJgyCkSDvCtA9YJxHbf
# 5aaBladG2oJXqZWSxbaPAyJsM3fBezIXbgfOWhRBOgUkG/YUBjuoJSQOu8wqdd25
# cEE/fNBjNiEHH0b/YKSR4We83h9+GRTJY2eR6mcHa7SPi8BuQ33DoYBssh68U4V9
# 3JChpLwt70ZyVzUFv7tGu25tN5m2/yOSkcZuQPiPKVbqX9VfFFOs8E9h6vcizKdW
# C+K4NB8m2XsZBWg/ujzUOAai0+aPDuO0cW1AQsWEtECVK/RloEh59h2BY5adT3Xg
# +HzkjqnR8q2Ks4zHIc3C7zCCBa4wggSWoAMCAQICEAcDcdEPeVpAcZkrlAdim+Iw
# DQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxCzAJBgNVBAgTAk1JMRIwEAYD
# VQQHEwlBbm4gQXJib3IxEjAQBgNVBAoTCUludGVybmV0MjERMA8GA1UECxMISW5D
# b21tb24xJTAjBgNVBAMTHEluQ29tbW9uIFJTQSBDb2RlIFNpZ25pbmcgQ0EwHhcN
# MTgwNjIxMDAwMDAwWhcNMjEwNjIwMjM1OTU5WjCBuTELMAkGA1UEBhMCVVMxDjAM
# BgNVBBEMBTgwMjA0MQswCQYDVQQIDAJDTzEPMA0GA1UEBwwGRGVudmVyMRgwFgYD
# VQQJDA8xMjAxIDV0aCBTdHJlZXQxMDAuBgNVBAoMJ01ldHJvcG9saXRhbiBTdGF0
# ZSBVbml2ZXJzaXR5IG9mIERlbnZlcjEwMC4GA1UEAwwnTWV0cm9wb2xpdGFuIFN0
# YXRlIFVuaXZlcnNpdHkgb2YgRGVudmVyMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A
# MIIBCgKCAQEAy1eJKMQONg0Ehhew+cUYfBmq9LmWBE1JpCOzLGAuwYjrIssMKlpj
# LcIHA3WifhCdjMRCmwdX5Mn/crrVm+oDGFHoCfDxONWNoHeQ920omMRSWCJc0rSc
# NHIxVqxnJ5cAtHlJNJ/VLGgy3wcgN3QpMHzKEwTp7MV0XPAHkd7b+PI6zB9iw36f
# iTZD1RxpW1aALNa5rf1qfA29rszga6A87lmQXpeSsbNEeldy1X8WTouao9jqxGbj
# mdJycLUpDc03+3pkEfOYC2BtlrjWjn4C812S/1NUXpLc4Mal/eopbySMW3zYsth1
# mLRXTuWf5L8G0CUZQ86+p6bgSRsy1nkzcwIDAQABo4IB7DCCAegwHwYDVR0jBBgw
# FoAUrjUjF///Bj2cUOCMJGUzHnAQiKIwHQYDVR0OBBYEFKXpiG68+Uil9fM4ir5j
# +aQMY5sPMA4GA1UdDwEB/wQEAwIHgDAMBgNVHRMBAf8EAjAAMBMGA1UdJQQMMAoG
# CCsGAQUFBwMDMBEGCWCGSAGG+EIBAQQEAwIEEDBmBgNVHSAEXzBdMFsGDCsGAQQB
# riMBBAMCATBLMEkGCCsGAQUFBwIBFj1odHRwczovL3d3dy5pbmNvbW1vbi5vcmcv
# Y2VydC9yZXBvc2l0b3J5L2Nwc19jb2RlX3NpZ25pbmcucGRmMEkGA1UdHwRCMEAw
# PqA8oDqGOGh0dHA6Ly9jcmwuaW5jb21tb24tcnNhLm9yZy9JbkNvbW1vblJTQUNv
# ZGVTaWduaW5nQ0EuY3JsMH4GCCsGAQUFBwEBBHIwcDBEBggrBgEFBQcwAoY4aHR0
# cDovL2NydC5pbmNvbW1vbi1yc2Eub3JnL0luQ29tbW9uUlNBQ29kZVNpZ25pbmdD
# QS5jcnQwKAYIKwYBBQUHMAGGHGh0dHA6Ly9vY3NwLmluY29tbW9uLXJzYS5vcmcw
# LQYDVR0RBCYwJIEiaXRzc3lzdGVtZW5naW5lZXJpbmdAbXN1ZGVudmVyLmVkdTAN
# BgkqhkiG9w0BAQsFAAOCAQEAhzY9WrsFqZYC6PIJA8ewYINszeLU5jmeu4D9861s
# nqYm9P1Qljj7rWCtwcvNXuinXLSdGFXjn1Osp8co7ja5HJml2cdo6gLTzRx+D/QT
# AUlHLdtgHS+RU/xN5SS9SFu1w9Wh8jU//CH1lPaJhUJ6s44CqK/FaqHwO37yhJuN
# IaE8VbK7ThvxRzNsr/3u5d2ArTM1xcMlSMwqvoJt698tAt9CIU+LNp6P7Z+9H+Nk
# cC/E71bauF3o3DqAWzarc/gIUrT7ICQUIuT73Cyn5GxG9GS91Ymn5qc28Ao7JV8K
# PqzPl1A8AhgjIuHL3N7e1pUqb30NBBlX/A38BM8N+0sabTCCBeswggPToAMCAQIC
# EGXh4uPV3lBFhfMmJIAF4tQwDQYJKoZIhvcNAQENBQAwgYgxCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpOZXcgSmVyc2V5MRQwEgYDVQQHEwtKZXJzZXkgQ2l0eTEeMBwG
# A1UEChMVVGhlIFVTRVJUUlVTVCBOZXR3b3JrMS4wLAYDVQQDEyVVU0VSVHJ1c3Qg
# UlNBIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MB4XDTE0MDkxOTAwMDAwMFoXDTI0
# MDkxODIzNTk1OVowfDELMAkGA1UEBhMCVVMxCzAJBgNVBAgTAk1JMRIwEAYDVQQH
# EwlBbm4gQXJib3IxEjAQBgNVBAoTCUludGVybmV0MjERMA8GA1UECxMISW5Db21t
# b24xJTAjBgNVBAMTHEluQ29tbW9uIFJTQSBDb2RlIFNpZ25pbmcgQ0EwggEiMA0G
# CSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDAoC+LHnq7anWs+D7co7o5Isrzo3bk
# v30wJ+a605gyViNcBoaXDYDo7aKBNesL9l5+qT5oc/2d1Gd5zqrqaLcZ2xx2OlmH
# XV6Zx6GyuKmEcwzMq4dGHGrH7zklvqfd2iw1cDYdIi4gO93jHA4/NJ/lff5VgFsG
# fIJXhFXzOPvyDDapuV6yxYFHI30SgaDAASg+A/k4l6OtAvICaP3VAav11VFNUNMX
# IkblcxjgOuQ3d1HInn1Sik+A3Ca5wEzK/FH6EAkRelcqc8TgISpswlS9HD6D+Fup
# LPH623jP2YmabaP/Dac/fkxWI9YJvuGlHYsHxb/j31iq76SvgssF+AoJAgMBAAGj
# ggFaMIIBVjAfBgNVHSMEGDAWgBRTeb9aqitKz1SA4dibwJ3ysgNmyzAdBgNVHQ4E
# FgQUrjUjF///Bj2cUOCMJGUzHnAQiKIwDgYDVR0PAQH/BAQDAgGGMBIGA1UdEwEB
# /wQIMAYBAf8CAQAwEwYDVR0lBAwwCgYIKwYBBQUHAwMwEQYDVR0gBAowCDAGBgRV
# HSAAMFAGA1UdHwRJMEcwRaBDoEGGP2h0dHA6Ly9jcmwudXNlcnRydXN0LmNvbS9V
# U0VSVHJ1c3RSU0FDZXJ0aWZpY2F0aW9uQXV0aG9yaXR5LmNybDB2BggrBgEFBQcB
# AQRqMGgwPwYIKwYBBQUHMAKGM2h0dHA6Ly9jcnQudXNlcnRydXN0LmNvbS9VU0VS
# VHJ1c3RSU0FBZGRUcnVzdENBLmNydDAlBggrBgEFBQcwAYYZaHR0cDovL29jc3Au
# dXNlcnRydXN0LmNvbTANBgkqhkiG9w0BAQ0FAAOCAgEARiy2f2pOJWa9nGqmqtCe
# vQ+uTjX88DgnwcedBMmCNNuG4RP3wZaNMEQT0jXtefdXXJOmEldtq3mXwSZk38lc
# y8M2om2TI6HbqjACa+q4wIXWkqJBbK4MOWXFH0wQKnrEXjCcfUxyzhZ4s6tA/L4L
# mRYTmCD/srpz0bVU3AuSX+mj05E+WPEop4WE+D35OLcnMcjFbst3KWN99xxaK40V
# HnX8EkcBkipQPDcuyt1hbOCDjHTq2Ay84R/SchN6WkVPGpW8y0mGc59lul1dlDmj
# VOynF9MRU5ACynTkdQ0JfKHOeVUuvQlo2Qzt52CTn3OZ1NtIZ0yrxm267pXKuK86
# UxI9aZrLkyO/BPO42itvAG/QMv7tzJkGns1hmi74OgZ3WUVk3SNTkixAqCbf7TSm
# ecnrtyt0XB/P/xurcyFOIo5YRvTgVPc5lWn6PO9oKEdYtDyBsI5GAKVpmrUfdqoj
# sl5GRYQQSnpO/hYBWyv+LsuhdTvaA5vwIDM8WrAjgTFx2vGnQjg5dsQIeUOpTixM
# ierCUzCh+bF47i73jX3qoiolCX7xLKSXTpWS2oy7HzgjDdlAsfTwnwton5YNTJxz
# g6NjrUjsUbEIORtJB/eeld5EWbQgGfwaJb5NEOTonZckUtYS1VmaFugWUEuhSWod
# QIq7RA6FT/4AQ6qdj3yPbNExggTpMIIE5QIBATCBkDB8MQswCQYDVQQGEwJVUzEL
# MAkGA1UECBMCTUkxEjAQBgNVBAcTCUFubiBBcmJvcjESMBAGA1UEChMJSW50ZXJu
# ZXQyMREwDwYDVQQLEwhJbkNvbW1vbjElMCMGA1UEAxMcSW5Db21tb24gUlNBIENv
# ZGUgU2lnbmluZyBDQQIQBwNx0Q95WkBxmSuUB2Kb4jANBglghkgBZQMEAgEFAKCB
# hDAYBgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEE
# AYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMC8GCSqGSIb3DQEJ
# BDEiBCB5rJmKDOeW1bgCFU90Rx3ylgBKieiYaDh0+k5Xv028ezANBgkqhkiG9w0B
# AQEFAASCAQCiRukuCiUNXBT7QAWpY5ACF7+Oms7E3eENnY6aHENJVf0rELK3eWhz
# r3gWKni/tqyDvY+WewaAh2seqGYlIMugZoro7Me9oAUdwL8Ay4NmlULYIUj52kNK
# zmgFyd00AWWoYhl0yzDSE1Wed2wkYs5WZXcbMUtkFa+yNN+NosV1IJNknfSilD//
# 4mkKE+paZNy9zfadmnJNpOWu75nlNTV5sAAmqyaHrXmUMjmlLiziqbY+ZSXN3n3B
# ew1eQR8c+2n5gQwAsshM8V3MouXSidMsFHw7jHmuukYbZXGabITGP9x7/O4gG9MF
# iKNoI47lqAzFGkfufN+6tXljUOIrZIKYoYICojCCAp4GCSqGSIb3DQEJBjGCAo8w
# ggKLAgEBMGgwUjELMAkGA1UEBhMCQkUxGTAXBgNVBAoTEEdsb2JhbFNpZ24gbnYt
# c2ExKDAmBgNVBAMTH0dsb2JhbFNpZ24gVGltZXN0YW1waW5nIENBIC0gRzICEhEh
# 1pmnZJc+8fhCfukZzFNBFDAJBgUrDgMCGgUAoIH9MBgGCSqGSIb3DQEJAzELBgkq
# hkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTE4MDYyNTE3MTAxMVowIwYJKoZIhvcN
# AQkEMRYEFExHiNLIrvt1kjJymDOWVFZFZ4xFMIGdBgsqhkiG9w0BCRACDDGBjTCB
# ijCBhzCBhAQUY7gvq2H1g5CWlQULACScUCkz7HkwbDBWpFQwUjELMAkGA1UEBhMC
# QkUxGTAXBgNVBAoTEEdsb2JhbFNpZ24gbnYtc2ExKDAmBgNVBAMTH0dsb2JhbFNp
# Z24gVGltZXN0YW1waW5nIENBIC0gRzICEhEh1pmnZJc+8fhCfukZzFNBFDANBgkq
# hkiG9w0BAQEFAASCAQBSR4h01SDTJc4oqiQsgHUrBz0cLfuxMkrkzhbcSquFaUht
# f6G4ieIMD3lKrjps6CShtDnEItm3EsD2GU7A+xh2hxhJTNxFs4gNyFwMdBZhSjov
# CG0V8f2Yae6+mbfdxtKdJ4a3o3yu4Cr07E1AOwUFsLEQX/cLYL0y9MSnng5fa0m3
# PaGBaMkpxO6bTQwpxR179q6te7SlBeknG1zgiVGpDs4PHrVwegozazYDqFtTeFmG
# ezDXlJSvGt1DajQbAoaYFX5vqRjHi6agy6hiAcp4NhTqdTcu05oZ1nzJAlDk0xOC
# 9GOsbjxT/sraOiIoDAD0IuMcDrjKjccCo756JAWm
# SIG # End signature block
