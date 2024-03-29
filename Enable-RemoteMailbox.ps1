[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    $Body,
    [Parameter(Mandatory = $false)]
    [string]$ExchangeServer,
    [Parameter(Mandatory = $true)]
    [int]$formatVariant = 1
)

#Start-Transcript -Path C:\temp\transcript_$(Get-Date -Format "yyyyMMdd_HHmmss").txt

Import-Module ActiveDirectory

function GenerateEmail {
    param (
        [string]$givenName,
        [string]$middleName,
        [string]$familyName,
        [string]$domainName,
        [int]$formatVariant = 1
    )
    function NormalizeDiacritics($text) {
        $normalizedString = $text.Normalize([Text.NormalizationForm]::FormD)
        $charArray = $normalizedString.ToCharArray()
    
        $sb = New-Object Text.StringBuilder
        foreach ($c in $charArray) {
            $unicodeCategory = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($c)
            if ($unicodeCategory -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
                [void]$sb.Append($c)
            }
        }
    
        return $sb.ToString()
    }
      

    function StripSpaces($text) {
        return $text -replace '\s', ''
    }

    function GetInitials($name) {
        $splitName = $name -split ' '
        $initials = $splitName | ForEach-Object { $_.Substring(0, 1) }
        return -join $initials
    }

    function GenerateBaseEmail {
        $initials = GetInitials $givenName
        $emailLocalPart = ""
    
        $normalizedGivenName = NormalizeDiacritics($givenName).Replace(" ", "").ToLower()
        $normalizedFamilyName = NormalizeDiacritics($familyName).Replace(" ", "").ToLower()
        $normalizedMiddleName = if ($middleName) { NormalizeDiacritics($middleName).Replace(" ", "").ToLower() } else { "" }
    
        switch ($formatVariant) {
            1 { $emailLocalPart = @($initials, $normalizedMiddleName, $normalizedFamilyName) -join '.' -replace '\.{2,}', '.' }
            2 { $emailLocalPart = ($initials + $normalizedMiddleName + $normalizedFamilyName) -replace '\.{2,}', '.' }
            3 { $emailLocalPart = @($normalizedGivenName, $normalizedMiddleName + $normalizedFamilyName) -join '.' -replace '\.{2,}', '.' }
            4 { $emailLocalPart = ($normalizedGivenName + $normalizedMiddleName + $normalizedFamilyName) -replace '\.{2,}', '.' }
            5 { $emailLocalPart = ($initials + $normalizedMiddleName + $normalizedFamilyName) -replace '\.{2,}', '.' }
            6 { $emailLocalPart = ($initials + '.' + $normalizedMiddleName + $normalizedFamilyName).Trim('.') }
            7 { 
                $firstInitial = $normalizedGivenName.Substring(0, 1)
                $middleInitials = if ($middleName) { GetInitials $middleName } else { "" }
                $emailLocalPart = $firstInitial + $middleInitials + $normalizedFamilyName
            }
            default { $emailLocalPart = @($initials, $normalizedMiddleName, $normalizedFamilyName) -join '.' -replace '\.{2,}', '.' }
        }
    
        return ("$emailLocalPart@$domainName").ToLower()
    }
    
    

    # Main email generation logic
    $baseEmail = GenerateBaseEmail
    return $baseEmail
}

foreach ($user in $Body.Operations) {
    # Access the 'data' property of the user object
    $userData = $user.data

    # Check if the userData object has the 'name' property with 'familyName' and 'givenName' sub-properties
    if ($userData.PSObject.Properties.Name -contains "name" -and $userData.name.PSObject.Properties.Name -contains "familyName" -and $userData.name.PSObject.Properties.Name -contains "givenName") {
        # This is the correct user format, process further
        #Write-Host "Processing user: $($userData.name.familyName), $($userData.name.givenName)"

        $givenName = $user.data.name.givenName
        $familyName = $user.data.name.familyName
        $middlename = $user.data.'urn:ietf:params:scim:schemas:extension:CustomExtensionName:2.0:User'.middlename
        $domainname = $user.data.'urn:ietf:params:scim:schemas:extension:CustomExtensionName:2.0:User'.domainname

        $constructedUPN = GenerateEmail -givenName $givenName -middleName $middlename -familyName $familyName -domainName $domainname -formatVariant $formatVariant
  
        Write-Output ("constructedUPN")
        $constructedUPN
  
        $aduser = Get-ADUser -Filter "UserPrincipalName -eq '$constructedUPN'"

        $Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri http://$ExchangeServer/PowerShell/ -Authentication Kerberos

        Import-PSSession $Session

        if (!(Get-RemoteMailbox -Identity $aduser.SamAccountName -ErrorAction silentlycontinue)){
       
        Enable-RemoteMailbox -Identity $aduser.SamAccountName -RemoteRoutingAddress $aduser.UserPrincipalName

        }

        Remove-PSSession $Session


    } else {
        # This is not the correct user format, skip it
        Write-Output "Skipping user object due to incorrect format > probably a manager object"

    }

}

#Stop-Transcript
