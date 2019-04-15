﻿#Download Microsoft Online Services Sign In Assistant for IT Proffessionals RTW x64
#https://www.microsoft.com/en-us/download/details.aspx?id=41950

#https://supertekboy.com/2018/11/07/connect-msolservice-may-fail-when-mfa-is-enabled/

<#
.SYNOPSIS
Add Users and assign licenses and import pictures.

If tempPassword isn't set the password will be P@55w0rd

You will need to connect to Azure AD first using Connect-AzureAD
You will need to connect to MSO using Connect-MsolService

.EXAMPLE

.\Set-UserAccountOnline.ps1 -Path:'.\AzureADUser.csv' -tenantDomain:'mytenant.onmicrosoft.com' -tempPassword:'U$kd8*2BG'
#>

param(
    # The path to the CSV file
    [Parameter(Mandatory)][string]$Path,

    # The tenant Domain
    [Parameter(Mandatory)][string]$TenantDomain,

    #The temporary password
    [string]$TempPassword
)
try
{
Import-Module AzureAD
Import-Module MSOnline
}
catch
{
    Write-Error "Unable to find Module AzureAD, or MSOnline"
    return
}

$ErrorActionPreference = 'stop'

# Show basic information
$InformationPreference = 'continue'


Write-Information -MessageData:"$(Get-Date) Started populating the AD tenant for $TenantDomain."

#Setup temp password
$dummyPasswordProfile = New-Object -TypeName Microsoft.Open.AzureAD.Model.PasswordProfile
if($null -eq $tempPassword){
    $tempPassword = "P@55w0rd"
}
$dummyPasswordProfile.Password = $tempPassword
$dummyPasswordProfile.ForceChangePasswordNextLogin = $true

$st = New-Object -TypeName Microsoft.Online.Administration.StrongAuthenticationRequirement
$st.RelyingParty = "*"
$st.State = "Enabled"
$sta = @($st)



@($(Import-csv -path:$Path)).ForEach({
    $UserCSV = $PSItem
    $UPN = $UserCSV.UserPrincipalName + '@' + $TenantDomain
    $DisplayName = $UserCSV.GivenName + ' ' + $UserCSV.Surname
    
    #Replace values that are empty with $null
    
    $user = Get-AzureADUser -Filter "userPrincipalName eq '$UPN'"
    if(!$user){
      Write-Information -MessageData:"Creating user details $DisplayName"
      New-AzureADUser  -UserPrincipalName $UPN `
                -PasswordProfile $dummyPasswordProfile `
               -AccountEnabled ([System.Convert]::ToBoolean($UserCSV.AccountEnabled)) `
                -GivenName $UserCSV.GivenName `
                -DisplayName $DisplayName `
                -Surname $UserCSV.Surname `
                -MailNickName $UserCSV.MailNickName `
                -JobTitle $UserCSV.JobTitle `
                -Department $UserCSV.Department `
                -Mobile $UserCSV.Mobile `
                -TelephoneNumber $UserCSV.Telephone `
                -PhysicalDeliveryOfficeName $UserCSV.Office `
                -StreetAddress $UserCSV.StreetAddress `
                -City $UserCSV.City `
                -Country $UserCSV.Country `
                -State $UserCSV.State `
                -PostalCode $UserCSV.PostCode `
                -ShowInAddressList $UserCSV.ShowInAddressList `
                -UsageLocation $UserCSV.UsageLocation
    }
    else
    {
     #Replace values that are empty with $null

     Write-Information -MessageData:"Updating user details $DisplayName"
     #Update user
     Set-AzureADUser -ObjectId $user.ObjectId `
                -AccountEnabled ([System.Convert]::ToBoolean($UserCSV.AccountEnabled)) `
                -GivenName $UserCSV.GivenName `
                -DisplayName $DisplayName `
                -Surname $UserCSV.Surname `
                -MailNickName $UserCSV.MailNickName `
                -JobTitle $UserCSV.JobTitle `
                -Department $UserCSV.Department `
                -Mobile $UserCSV.Mobile `
                -TelephoneNumber $UserCSV.Telephone `
                -PhysicalDeliveryOfficeName $UserCSV.Office `
                -StreetAddress $UserCSV.StreetAddress `
                -City $UserCSV.City `
                -Country $UserCSV.Country `
                -State $UserCSV.State `
                -PostalCode $UserCSV.PostCode `
                -ShowInAddressList ([System.Convert]::ToBoolean($UserCSV.ShowInAddressList)) `
                -UsageLocation $UserCSV.UsageLocation
    }

    if($UserCSV.MFAEnabled)
    {  
        Write-Information -MessageData:"Enabling MFA for $DisplayName"
        Set-MsolUser -UserPrincipalName $UPN -StrongAuthenticationRequirements $sta
    }
    else
    {
        Write-Information -MessageData:"Disabling MFA for $DisplayName"
        Set-MsolUser -UserPrincipalName $UPN -StrongAuthenticationRequirements @()
    }
    
    #Assign Manager
    $manager = Get-AzureADUser -Filter "DisplayName eq '$DisplayName'"
    if($manager){
        Write-Information -MessageData:"Found Manager and assigning for $DisplayName"
        $UserManager = Set-AzureADUserManager -ObjectId $user.ObjectId -RefObjectId $manager.ObjectId 
    }

    $license = New-Object -TypeName Microsoft.Open.AzureAD.Model.AssignedLicense
    $licenses = New-Object -TypeName Microsoft.Open.AzureAD.Model.AssignedLicenses

    $SKU = Get-AzureADSubscribedSku | Where-Object -Property SkuPartNumber -Value $UserCSV.License -EQ
    if($null -eq $SKU)
    {
        Write-Warning -Message:"No License type found called $($UserCSV.License)"
    }
    else
    {
        $license.SkuId = $SKU.SkuId
        $licenses.AddLicenses = $license

        if($SKU.ConsumedUnits -ge $SKU.PrepaidUnits.Enabled)
        {
            Write-Warning -Message:"No licenses of:$($UserCSV.License) available in Tenant"
        }
        else
        { 
            Write-Information -MessageData:"Assigning license:$($UserCSV.License) to $DisplayName"
            $remaining =  $SKU.PrepaidUnits.Enabled - $SKU.ConsumedUnits
            $userLicense = Set-AzureADUserLicense -ObjectId $user.ObjectId -AssignedLicenses $licenses
            Write-Information -MessageData:"There are $remaining licenses $($UserCSV.License) left"
        }
    }
    $ImageName = $DisplayName -replace '\.',' '
    if(Test-Path -path:"$PSScriptRoot\UserImages\$ImageName.jpg")
    {
     Write-Information -MessageData:"Setting UserPhoto for $DisplayName"
     $UserPhoto = Set-AzureADUserThumbnailPhoto -ObjectId $user.ObjectId -FilePath "$PSScriptRoot\UserImages\$DisplayName.jpg"
    }
    else
    {
      Write-Warning -Message:"Unable to find picture for $DisplayName"
    }
})

#Upload Photo
#>
Write-Host "Finished uploading Data at $(Get-Date)"
