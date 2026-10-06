@{
    RootModule        = 'NameGender.psm1'
    ModuleVersion     = '0.3.0'
    GUID              = '6f3c2a9e-8d41-4b7a-9c5e-2f1d0a7b8e43'
    Author            = 'NameGender'
    CompanyName       = 'NameGender'
    Copyright         = '(c) 2026 NameGender. MIT License.'
    Description       = 'PowerShell client for the NameGender API: gender from names, email addresses and usernames, with the probability and sample size behind each answer, salutations for letters and emails, and a check of whether a name typed into a form looks like a real person''s name.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport = @('Get-NameGender', 'Get-NameGenderCountry', 'Get-NameGenderAccount', 'Get-NameGenderSalutation', 'Test-NameGenderName')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @('gender', 'name', 'api', 'namegender', 'gender-detection')
            LicenseUri   = 'https://github.com/anpekesen/namegender-powershell/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/anpekesen/namegender-powershell'
            ReleaseNotes = '0.3.0: Test-NameGenderName says whether names look like real people''s names (plausible, suspicious or implausible, with the signals behind it). 0.2.0: Get-NameGenderSalutation builds formal, informal and neutral salutations from names.'
        }
    }
}
