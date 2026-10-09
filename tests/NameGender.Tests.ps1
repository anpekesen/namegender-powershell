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

Describe 'Get-NameGenderSalutation' {
    BeforeEach {
        $env:NAMEGENDER_API_KEY = 'ng_live_test'
        Remove-Item Env:NAMEGENDER_BASE_URL -ErrorAction SilentlyContinue

        Mock -ModuleName NameGender Invoke-RestMethod {
            $sent = [System.Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json
            if ($sent.PSObject.Properties['language'] -and $sent.language -eq 'xx') {
                $record = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Response status code does not indicate success: 422'), 'HttpError', 'InvalidOperation', $null)
                $record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new(
                    '{"error":"invalid_input","message":"Unsupported language.","field":"language","supported":["en","de","tr"],"request_id":"req_3"}')
                throw $record
            }
            if ($Uri -like '*/salutation/bulk') {
                $results = @($sent.names | ForEach-Object {
                    if ($_ -eq 'Kim Lee') {
                        [pscustomobject]@{
                            query = $_; language = 'de'; form = 'neutral'; reason = 'gender_unknown'
                            salutation = [pscustomobject]@{ formal = 'Guten Tag Kim Lee,'; informal = 'Hallo Kim Lee,'; neutral = 'Guten Tag Kim Lee,' }
                            parts = [pscustomobject]@{ opening = 'Guten Tag'; courtesy = $null; academic = $null; name = 'Kim Lee' }
                            gender = $null; probability = $null
                        }
                    } else {
                        [pscustomobject]@{
                            query = $_; language = 'de'; form = 'gendered'; reason = $null
                            salutation = [pscustomobject]@{ formal = "Sehr geehrte Frau $_,"; informal = "Liebe $_,"; neutral = "Guten Tag $_," }
                            parts = [pscustomobject]@{ opening = 'Sehr geehrte'; courtesy = 'Frau'; academic = $null; name = $_ }
                            gender = 'female'; probability = 98
                        }
                    }
                })
                [pscustomobject]@{
                    credits_charged = $results.Count; language = 'de'
                    summary = [pscustomobject]@{ total = $results.Count; gendered = $results.Count; neutral = 0; organization = 0 }
                    results = $results
                }
            } else {
                [pscustomobject]@{
                    credits_charged = 1; credits_remaining = 4999; query = 'Dr. Anna Müller'; language = 'de'; form = 'gendered'; reason = $null
                    salutation = [pscustomobject]@{ formal = 'Sehr geehrte Frau Dr. Müller,'; informal = 'Liebe Anna,'; neutral = 'Guten Tag Dr. Anna Müller,' }
                    parts = [pscustomobject]@{ opening = 'Sehr geehrte'; courtesy = 'Frau'; academic = 'Dr.'; name = 'Müller' }
                    gender = 'female'; gender_source = 'lookup'; probability = 99; name_type = 'personal'; country = 'DE'
                }
            }
        }
    }

    It 'sends one name to /salutation with only the options that were given' {
        $result = Get-NameGenderSalutation 'Dr. Anna Müller' -Language de -Country de

        $result.salutation.formal | Should -Be 'Sehr geehrte Frau Dr. Müller,'
        $result.salutation.informal | Should -Be 'Liebe Anna,'
        $result.salutation.neutral | Should -Be 'Guten Tag Dr. Anna Müller,'
        $result.reason | Should -BeNullOrEmpty
        $result.parts.academic | Should -Be 'Dr.'
        Should -Invoke -ModuleName NameGender Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $sent = [System.Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json
            $Uri -eq 'https://namegender.com/api/v1/salutation' -and $Method -eq 'POST' -and
            (($sent.PSObject.Properties.Name | Sort-Object) -join ',') -eq 'country,language,name' -and
            $sent.name -eq 'Dr. Anna Müller' -and $sent.country -eq 'DE' -and $sent.language -eq 'de'
        }
    }

    It 'sends first and last name, gender, title and minimum probability' {
        Get-NameGenderSalutation -FirstName Anna -LastName 'Müller' -Gender Female -Title 'Dr.' -MinProbability 80 | Out-Null

        Should -Invoke -ModuleName NameGender Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $sent = [System.Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json
            $Uri -like '*/salutation' -and
            (($sent.PSObject.Properties.Name | Sort-Object) -join ',') -eq 'first_name,gender,last_name,min_probability,title' -and
            $sent.first_name -eq 'Anna' -and $sent.last_name -eq 'Müller' -and $sent.gender -eq 'female' -and
            $sent.title -eq 'Dr.' -and $sent.min_probability -eq 80
        }
    }

    It 'returns only the chosen form with -Form' {
        Get-NameGenderSalutation 'Dr. Anna Müller' -Form informal | Should -Be 'Liebe Anna,'
    }

    It 'collects pipeline input into one bulk request, keeps the order and skips blank lines' {
        $results = 'Anna Müller', '', '  Kim Lee  ', 'Eva Weber' | Get-NameGenderSalutation -Language de

        @($results).Count | Should -Be 3
        ($results.query -join ',') | Should -Be 'Anna Müller,Kim Lee,Eva Weber'
        $results[0].reason | Should -BeNullOrEmpty
        $results[1].form | Should -Be 'neutral'
        $results[1].reason | Should -Be 'gender_unknown'
        $results[1].parts.courtesy | Should -BeNullOrEmpty
        Should -Invoke -ModuleName NameGender Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $sent = [System.Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json
            $Uri -like '*/salutation/bulk' -and ($sent.names -join ',') -eq 'Anna Müller,Kim Lee,Eva Weber' -and
            (($sent.PSObject.Properties.Name | Sort-Object) -join ',') -eq 'language,names'
        }
    }

    It 'splits more than 100 names into chunks of 100 and applies -Form to each' {
        $names = 1..205 | ForEach-Object { "Name$_" }
        $results = $names | Get-NameGenderSalutation -Form formal

        @($results).Count | Should -Be 205
        $results[0] | Should -Be 'Sehr geehrte Frau Name1,'
        $results[204] | Should -Be 'Sehr geehrte Frau Name205,'
        Should -Invoke -ModuleName NameGender Invoke-RestMethod -Times 3 -Exactly
        Should -Invoke -ModuleName NameGender Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            @(([System.Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json).names).Count -eq 5
        }
    }

    It 'throws the API reason, field and supported languages for an unsupported language' {
        $caught = $null
        try { Get-NameGenderSalutation 'Ahmet Yılmaz' -Language xx } catch { $caught = $_ }

        $caught | Should -Not -BeNullOrEmpty
        $caught.Exception.Message | Should -Be 'Unsupported language. (invalid_input)'
        $caught.Exception.Data['error'] | Should -Be 'invalid_input'
        $caught.Exception.Data['field'] | Should -Be 'language'
        ($caught.Exception.Data['supported'] -join ',') | Should -Be 'en,de,tr'
    }

    It 'rejects invalid options before any request' {
        { Get-NameGenderSalutation 'Anna Müller' -Gender other } | Should -Throw
        { Get-NameGenderSalutation 'Anna Müller' -MinProbability 40 } | Should -Throw
        { Get-NameGenderSalutation 'Anna Müller' -Form casual } | Should -Throw
        { Get-NameGenderSalutation -FirstName '' } | Should -Throw
        Should -Invoke -ModuleName NameGender Invoke-RestMethod -Times 0
    }
}

Describe 'Test-NameGenderName' {
    BeforeEach {
        $env:NAMEGENDER_API_KEY = 'ng_live_test'
        Remove-Item Env:NAMEGENDER_BASE_URL -ErrorAction SilentlyContinue

        Mock -ModuleName NameGender Invoke-RestMethod {
            $sent = [System.Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json
            if ($sent.PSObject.Properties['name'] -and $sent.name -eq 'No Credit') {
                $record = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Response status code does not indicate success: 402'), 'HttpError', 'InvalidOperation', $null)
                $record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new(
                    '{"error":"no_credits","message":"No credits left.","request_id":"req_4"}')
                throw $record
            }
            $check = {
                param($query)
                if ($query -eq 'asdf qwerty') {
                    [pscustomobject]@{
                        query = $query; assessment = 'implausible'; score = 0
                        signals = @(
                            [pscustomobject]@{ code = 'keyboard_pattern'; severity = 'high'; part = 'first_name'; value = 'asdf' }
                            [pscustomobject]@{ code = 'single_name'; severity = 'low'; part = $null; value = $null }
                        )
                        first_name = 'Asdf'; last_name = 'Qwerty'; name_type = 'personal'
                        evidence = [pscustomobject]@{ first_name_status = $null; first_name_counted_records = 0 }
                    }
                } else {
                    [pscustomobject]@{
                        query = $query; assessment = 'plausible'; score = 95; signals = @()
                        first_name = 'Jennifer'; last_name = 'Null'; name_type = 'personal'
                        evidence = [pscustomobject]@{ first_name_status = 'counted'; first_name_counted_records = 1500000 }
                    }
                }
            }
            if ($Uri -like '*/name-check/bulk') {
                $results = @($sent.names | ForEach-Object { & $check $_ })
                [pscustomobject]@{
                    credits_charged = $results.Count; took_ms = 4; country_source = $null
                    summary = [pscustomobject]@{ total = $results.Count; plausible = 0; suspicious = 0; implausible = 0 }
                    results = $results
                }
            } else {
                $query = if ($sent.PSObject.Properties['name']) { $sent.name } else { 'Jennifer Null' }
                $result = & $check $query
                $result | Add-Member credits_charged 1
                $result | Add-Member credits_remaining 4999
                $result | Add-Member country_source 'ip'
                $result
            }
        }
    }

    It 'sends one name to /name-check with only the options that were given' {
        $result = Test-NameGenderName 'asdf qwerty' -Ip 203.0.113.7

        $result.assessment | Should -Be 'implausible'
        $result.score | Should -Be 0
        $result.country_source | Should -Be 'ip'
        $result.signals[0].code | Should -Be 'keyboard_pattern'
        $result.signals[0].severity | Should -Be 'high'
        $result.signals[0].part | Should -Be 'first_name'
        $result.signals[0].value | Should -Be 'asdf'
        $result.signals[1].part | Should -BeNullOrEmpty
        $result.signals[1].value | Should -BeNullOrEmpty
        $result.evidence.first_name_status | Should -BeNullOrEmpty
        $result.evidence.first_name_counted_records | Should -Be 0
        Should -Invoke -ModuleName NameGender Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $sent = [System.Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json
            $Uri -eq 'https://namegender.com/api/v1/name-check' -and $Method -eq 'POST' -and
            (($sent.PSObject.Properties.Name | Sort-Object) -join ',') -eq 'ip,name' -and
            $sent.name -eq 'asdf qwerty' -and $sent.ip -eq '203.0.113.7'
        }
    }

    It 'sends first and last name with country and locale' {
        $result = Test-NameGenderName -FirstName Jennifer -LastName Null -Country us -Locale en-US

        $result.assessment | Should -Be 'plausible'
        $result.evidence.first_name_status | Should -Be 'counted'
        Should -Invoke -ModuleName NameGender Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $sent = [System.Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json
            $Uri -like '*/name-check' -and
            (($sent.PSObject.Properties.Name | Sort-Object) -join ',') -eq 'country,first_name,last_name,locale' -and
            $sent.first_name -eq 'Jennifer' -and $sent.last_name -eq 'Null' -and $sent.country -eq 'US' -and $sent.locale -eq 'en-US'
        }
    }

    It 'collects pipeline input into one bulk request, keeps the order and skips blank lines' {
        $results = 'Jennifer Null', '', '  asdf qwerty  ', 'Ayşe Yılmaz' | Test-NameGenderName -Country US

        @($results).Count | Should -Be 3
        ($results.query -join ',') | Should -Be 'Jennifer Null,asdf qwerty,Ayşe Yılmaz'
        ($results.assessment -join ',') | Should -Be 'plausible,implausible,plausible'
        Should -Invoke -ModuleName NameGender Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $sent = [System.Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json
            $Uri -like '*/name-check/bulk' -and ($sent.names -join ',') -eq 'Jennifer Null,asdf qwerty,Ayşe Yılmaz' -and
            (($sent.PSObject.Properties.Name | Sort-Object) -join ',') -eq 'country,names'
        }
    }

    It 'splits more than 100 names into chunks of 100' {
        $names = 1..205 | ForEach-Object { "Name$_" }
        $results = $names | Test-NameGenderName

        @($results).Count | Should -Be 205
        $results[0].query | Should -Be 'Name1'
        $results[204].query | Should -Be 'Name205'
        Should -Invoke -ModuleName NameGender Invoke-RestMethod -Times 3 -Exactly
        Should -Invoke -ModuleName NameGender Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            @(([System.Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json).names).Count -eq 5
        }
    }

    It 'throws the API reason code' {
        $caught = $null
        try { Test-NameGenderName 'No Credit' } catch { $caught = $_ }

        $caught | Should -Not -BeNullOrEmpty
        $caught.Exception.Message | Should -Be 'No credits left. (no_credits)'
        $caught.Exception.Data['error'] | Should -Be 'no_credits'
        $caught.Exception.Data['request_id'] | Should -Be 'req_4'
    }

    It 'rejects invalid options before any request' {
        { Test-NameGenderName 'Jennifer Null' -Country USA } | Should -Throw
        { Test-NameGenderName -FirstName '' } | Should -Throw
        { Test-NameGenderName 'Jennifer Null' -FirstName Jennifer } | Should -Throw
        Should -Invoke -ModuleName NameGender Invoke-RestMethod -Times 0
    }
}

Describe 'Get-NameGenderAge' {
    BeforeEach {
        $env:NAMEGENDER_API_KEY = 'ng_live_test'
        Remove-Item Env:NAMEGENDER_BASE_URL -ErrorAction SilentlyContinue

        Mock -ModuleName NameGender Invoke-RestMethod {
            $sent = [System.Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json
            $estimate = {
                param($name, $country)
                if ($country -and $country -ne 'US') {
                    [pscustomobject]@{
                        name = $name; first_name = $name; gender = $null; age = $null
                        age_range = $null; age_range_80 = $null; birth_year = $null
                        sample_size = 0; births = 0; country = $country; country_source = 'country'
                        source = $null; series = $null; reference_year = 2026; reason = 'country_not_covered'
                    }
                } else {
                    [pscustomobject]@{
                        name = $name; first_name = $name; gender = $null; age = 36
                        age_range = [pscustomobject]@{ low = 32; high = 38 }
                        age_range_80 = [pscustomobject]@{ low = 28; high = 41 }
                        birth_year = 1990; sample_size = 353775; births = 361434
                        country = 'US'; country_source = 'default'
                        source = 'ssa'; series = '1880-2024'; reference_year = 2026; reason = $null
                    }
                }
            }
            $country = if ($sent.PSObject.Properties['country']) { $sent.country } else { $null }
            if ($Uri -like '*/age/bulk') {
                [pscustomobject]@{
                    credits_charged = @($sent.names).Count; credits_remaining = 49000; request_id = 'req_2'
                    country_source = 'default'
                    results = @($sent.names | ForEach-Object { & $estimate $_ $country })
                }
            } else {
                $result = & $estimate $sent.name $country
                $charged = if ($result.reason -eq 'country_not_covered') { 0 } else { 1 }
                $result | Add-Member credits_charged $charged
                $result | Add-Member credits_remaining 49999
                $result | Add-Member request_id 'req_1'
                $result
            }
        }
    }

    It 'sends one name to /age with only the name and parses both ranges' {
        $result = Get-NameGenderAge Brittany

        $result.age | Should -Be 36
        $result.age_range.low | Should -Be 32
        $result.age_range.high | Should -Be 38
        $result.age_range_80.low | Should -Be 28
        $result.age_range_80.high | Should -Be 41
        $result.birth_year | Should -Be 1990
        $result.sample_size | Should -Be 353775
        $result.births | Should -Be 361434
        $result.country | Should -Be 'US'
        $result.country_source | Should -Be 'default'
        $result.source | Should -Be 'ssa'
        $result.series | Should -Be '1880-2024'
        $result.reference_year | Should -Be 2026
        $result.reason | Should -BeNullOrEmpty
        $result.gender | Should -BeNullOrEmpty
        $result.credits_charged | Should -Be 1
        Should -Invoke -ModuleName NameGender Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $sent = [System.Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json
            $Uri -eq 'https://namegender.com/api/v1/age' -and $Method -eq 'POST' -and
            $Headers.Authorization -eq 'Bearer ng_live_test' -and
            (($sent.PSObject.Properties.Name | Sort-Object) -join ',') -eq 'name' -and
            $sent.name -eq 'Brittany'
        }
    }

    It 'sends gender, country, locale and ip when given' {
        Get-NameGenderAge Brittany -Gender Female -Country us -Locale en-US -Ip 203.0.113.7 | Out-Null

        Should -Invoke -ModuleName NameGender Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $sent = [System.Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json
            $Uri -like '*/age' -and
            (($sent.PSObject.Properties.Name | Sort-Object) -join ',') -eq 'country,gender,ip,locale,name' -and
            $sent.gender -eq 'female' -and $sent.country -eq 'US' -and $sent.locale -eq 'en-US' -and $sent.ip -eq '203.0.113.7'
        }
    }

    It 'returns country_not_covered as a result with no age, not an error' {
        $result = Get-NameGenderAge Ayşe -Country TR

        $result.age | Should -BeNullOrEmpty
        $result.age_range | Should -BeNullOrEmpty
        $result.age_range_80 | Should -BeNullOrEmpty
        $result.birth_year | Should -BeNullOrEmpty
        $result.reason | Should -Be 'country_not_covered'
        $result.credits_charged | Should -Be 0
        $result.country | Should -Be 'TR'
    }

    It 'collects pipeline input into one bulk request, keeps the order and skips blank lines' {
        $results = 'Brittany', '', '  Emma  ', 'Olivia' | Get-NameGenderAge -Gender female

        @($results).Count | Should -Be 3
        ($results.name -join ',') | Should -Be 'Brittany,Emma,Olivia'
        $results[0].age_range.low | Should -Be 32
        Should -Invoke -ModuleName NameGender Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $sent = [System.Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json
            $Uri -like '*/age/bulk' -and ($sent.names -join ',') -eq 'Brittany,Emma,Olivia' -and
            (($sent.PSObject.Properties.Name | Sort-Object) -join ',') -eq 'gender,names'
        }
    }

    It 'splits more than 100 names into chunks of 100' {
        $names = 1..205 | ForEach-Object { "Name$_" }
        $results = $names | Get-NameGenderAge

        @($results).Count | Should -Be 205
        $results[0].name | Should -Be 'Name1'
        $results[204].name | Should -Be 'Name205'
        Should -Invoke -ModuleName NameGender Invoke-RestMethod -Times 3 -Exactly
    }

    It 'rejects invalid options before any request' {
        { Get-NameGenderAge Brittany -Gender neutral } | Should -Throw
        { Get-NameGenderAge Brittany -Country USA } | Should -Throw
        Should -Invoke -ModuleName NameGender Invoke-RestMethod -Times 0
    }
}

Describe 'Live API (optional)' -Skip:(-not $env:NAMEGENDER_LIVE_KEY) {
    It 'resolves a real name' {
        $result = Get-NameGender Emma -ApiKey $env:NAMEGENDER_LIVE_KEY
        $result.gender | Should -Be 'female'
    }
}
