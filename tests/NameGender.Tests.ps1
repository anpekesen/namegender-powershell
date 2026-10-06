BeforeAll {
    Import-Module "$PSScriptRoot/../NameGender/NameGender.psd1" -Force
}

Describe 'Get-NameGender' {
    BeforeEach {
        $env:NAMEGENDER_API_KEY = 'ng_live_test'
        Remove-Item Env:NAMEGENDER_BASE_URL -ErrorAction SilentlyContinue

        Mock -ModuleName NameGender Invoke-RestMethod {
            $sent = [System.Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json
            if ($Uri -like '*/gender/bulk') {
                [pscustomobject]@{
                    results = @($sent.names | ForEach-Object { [pscustomobject]@{ query = $_; gender = 'female'; probability = 97 } })
                }
            } else {
                [pscustomobject]@{ query = 'single'; gender = 'male'; probability = 95; country_source = 'country' }
            }
        }
    }

    It 'sends one name to the single endpoint with the key in the header' {
        $result = Get-NameGender Andrea -Country it

        $result.gender | Should -Be 'male'
        Should -Invoke -ModuleName NameGender Invoke-RestMethod -Times 1 -ParameterFilter {
            $sent = [System.Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json
            $Uri -eq 'https://namegender.com/api/v1/gender' -and
            $Method -eq 'POST' -and
            $Headers.Authorization -eq 'Bearer ng_live_test' -and
            $sent.name -eq 'Andrea' -and $sent.country -eq 'IT'
        }
    }

    It 'passes locale, ip and best guess' {
        Get-NameGender Andrea -Locale it-IT -Ip 93.42.1.1 -BestGuess | Out-Null

        Should -Invoke -ModuleName NameGender Invoke-RestMethod -Times 1 -ParameterFilter {
            $sent = [System.Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json
            $sent.locale -eq 'it-IT' -and $sent.ip -eq '93.42.1.1' -and $sent.best_guess -eq $true
        }
    }

    It 'sends non-ASCII names as UTF-8' {
        Get-NameGender 'Ayşe' | Out-Null

        Should -Invoke -ModuleName NameGender Invoke-RestMethod -Times 1 -ParameterFilter {
            ([System.Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json).name -eq 'Ayşe'
        }
    }

    It 'collects pipeline input into one bulk request and skips blank lines' {
        $results = 'Emma', '', '  Liam  ' | Get-NameGender

        @($results).Count | Should -Be 2
        Should -Invoke -ModuleName NameGender Invoke-RestMethod -Times 1 -ParameterFilter {
            $sent = [System.Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json
            $Uri -like '*/gender/bulk' -and ($sent.names -join ',') -eq 'Emma,Liam' -and $sent.type -eq 'name'
        }
    }

    It 'splits more than 100 values into chunks of 100' {
        $names = 1..205 | ForEach-Object { "Name$_" }
        $results = $names | Get-NameGender

        @($results).Count | Should -Be 205
        Should -Invoke -ModuleName NameGender Invoke-RestMethod -Times 3 -Exactly
    }

    It 'reads email addresses with -Email' {
        Get-NameGender -Email jane.doe@example.com | Out-Null

        Should -Invoke -ModuleName NameGender Invoke-RestMethod -Times 1 -ParameterFilter {
            $Uri -like '*/gender/email' -and
            ([System.Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json).email -eq 'jane.doe@example.com'
        }
    }

    It 'honours NAMEGENDER_BASE_URL' {
        $env:NAMEGENDER_BASE_URL = 'http://localhost:8000/api/v1/'
        Get-NameGender Emma | Out-Null

        Should -Invoke -ModuleName NameGender Invoke-RestMethod -Times 1 -ParameterFilter { $Uri -eq 'http://localhost:8000/api/v1/gender' }
    }

    It 'rejects a malformed country before any request' {
        { Get-NameGender Emma -Country ITA } | Should -Throw
        Should -Invoke -ModuleName NameGender Invoke-RestMethod -Times 0
    }

    It 'requires an API key' {
        Remove-Item Env:NAMEGENDER_API_KEY
        { Get-NameGender Emma } | Should -Throw '*NAMEGENDER_API_KEY*'
    }
}

Describe 'Get-NameGenderAccount and Get-NameGenderCountry' {
    BeforeEach {
        $env:NAMEGENDER_API_KEY = 'ng_live_test'
        Mock -ModuleName NameGender Invoke-RestMethod { [pscustomobject]@{ ok = $true } }
    }

    It 'calls /me with GET and no body' {
        Get-NameGenderAccount | Out-Null

        Should -Invoke -ModuleName NameGender Invoke-RestMethod -Times 1 -ParameterFilter {
            $Uri -like '*/me' -and $Method -eq 'GET' -and -not $Body
        }
    }

    It 'sends the name and limit to /gender/countries' {
        Get-NameGenderCountry Mehmet -Limit 10 | Out-Null

        Should -Invoke -ModuleName NameGender Invoke-RestMethod -Times 1 -ParameterFilter {
            $sent = [System.Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json
            $Uri -like '*/gender/countries' -and $sent.name -eq 'Mehmet' -and $sent.limit -eq 10
        }
    }
}

Describe 'Live API (optional)' -Skip:(-not $env:NAMEGENDER_LIVE_KEY) {
    It 'resolves a real name' {
        $result = Get-NameGender Emma -ApiKey $env:NAMEGENDER_LIVE_KEY
        $result.gender | Should -Be 'female'
    }
}
