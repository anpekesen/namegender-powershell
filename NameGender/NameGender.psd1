@{
    RootModule        = 'NameGender.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '6f3c2a9e-8d41-4b7a-9c5e-2f1d0a7b8e43'
    Author            = 'NameGender'
    CompanyName       = 'NameGender'
    Copyright         = '(c) 2026 NameGender. MIT License.'
    Description       = 'PowerShell client for the NameGender API: gender from names, email addresses and usernames, with the probability and sample size behind each answer.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport = @('Get-NameGender', 'Get-NameGenderCountry', 'Get-NameGenderAccount')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @('gender', 'name', 'api', 'namegender', 'gender-detection')
            LicenseUri   = 'https://github.com/anpekesen/namegender-powershell/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/anpekesen/namegender-powershell'
            ReleaseNotes = 'First release: Get-NameGender, Get-NameGenderCountry, Get-NameGenderAccount.'
        }
    }
}
