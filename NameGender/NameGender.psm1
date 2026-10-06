Set-StrictMode -Version Latest

$script:DefaultBaseUrl = 'https://namegender.com/api/v1'
# The API's bulk limit; longer pipelines are sent in chunks of this size.
$script:Chunk = 100

function Resolve-NameGenderKey {
    param([string] $ApiKey)

    if ($ApiKey) { return $ApiKey }
    if ($env:NAMEGENDER_API_KEY) { return $env:NAMEGENDER_API_KEY }

    throw 'No API key. Pass -ApiKey or set $env:NAMEGENDER_API_KEY (free key at https://namegender.com).'
}

function Invoke-NameGenderApi {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $ApiKey,
        [string] $Method = 'POST',
        [hashtable] $Body
    )

    $baseUrl = if ($env:NAMEGENDER_BASE_URL) { $env:NAMEGENDER_BASE_URL.TrimEnd('/') } else { $script:DefaultBaseUrl }
    $request = @{
        Uri         = $baseUrl + $Path
        Method      = $Method
        Headers     = @{ Authorization = "Bearer $ApiKey"; Accept = 'application/json' }
        ErrorAction = 'Stop'
    }

    if ($Body) {
        $request.ContentType = 'application/json; charset=utf-8'
        # UTF-8 bytes, not a string: Windows PowerShell 5.1 would otherwise send
        # names such as Ayşe in the system code page.
        $request.Body = [System.Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 5 -Compress))
    }

    try {
        Invoke-RestMethod @request
    } catch {
        # The API's error body is { error, message, request_id, docs }. Surface the
        # reason code so scripts can branch on it instead of on the message text.
        $details = $null
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            try { $details = $_.ErrorDetails.Message | ConvertFrom-Json } catch { $details = $null }
        }

        if ($details -and $details.PSObject.Properties['error']) {
            $exception = [System.Exception]::new("$($details.message) ($($details.error))")
            $exception.Data['error'] = $details.error
            $exception.Data['request_id'] = $details.request_id
            # 422 invalid_input names the field; an unsupported language also lists the supported ones.
            if ($details.PSObject.Properties['field']) { $exception.Data['field'] = $details.field }
            if ($details.PSObject.Properties['supported']) { $exception.Data['supported'] = [string[]] @($details.supported) }
            throw $exception
        }

        throw
    }
}

function Get-NameGender {
    <#
    .SYNOPSIS
    Looks up the gender behind names, email addresses or usernames.

    .DESCRIPTION
    One value calls the single endpoint; several values (from -Name or the
    pipeline) are sent in bulk requests of up to 100. Every value costs one
    credit, unknown results included. Results carry gender, probability,
    sample_size, country, confidence and source.

    .EXAMPLE
    Get-NameGender Andrea -Country IT

    .EXAMPLE
    Get-Content names.txt | Get-NameGender | Export-Csv genders.csv -NoTypeInformation

    .EXAMPLE
    Get-NameGender -Email jane.doe@example.com
    #>
    [CmdletBinding(DefaultParameterSetName = 'Name')]
    param(
        [Parameter(ParameterSetName = 'Name', Mandatory, Position = 0, ValueFromPipeline)]
        [AllowEmptyString()]
        [string[]] $Name,

        [Parameter(ParameterSetName = 'Email', Mandatory, ValueFromPipeline)]
        [AllowEmptyString()]
        [string[]] $Email,

        [Parameter(ParameterSetName = 'Username', Mandatory, ValueFromPipeline)]
        [AllowEmptyString()]
        [string[]] $Username,

        # Two-letter country code. Andrea is male in Italy and female in Germany.
        [ValidatePattern('^[A-Za-z]{2}$')]
        [string] $Country,

        # Language tag such as it-IT; its region is the country when -Country is absent.
        [string] $Locale,

        # End user IP address; its country is used when neither -Country nor a regional -Locale is sent.
        [string] $Ip,

        # Return the more likely gender even when the evidence is weak.
        [switch] $BestGuess,

        [string] $ApiKey
    )

    begin {
        $key = Resolve-NameGenderKey $ApiKey
        $values = [System.Collections.Generic.List[string]]::new()
        $type = $PSCmdlet.ParameterSetName.ToLowerInvariant()

        $options = @{}
        if ($Country) { $options.country = $Country.ToUpperInvariant() }
        if ($Locale) { $options.locale = $Locale }
        if ($Ip) { $options.ip = $Ip }
        if ($BestGuess) { $options.best_guess = $true }
    }

    process {
        # Blank lines are allowed in (Get-Content gives them) and dropped here.
        $batch = switch ($type) { 'email' { $Email } 'username' { $Username } default { $Name } }
        foreach ($value in $batch) {
            $trimmed = "$value".Trim()
            # Empty lines are not sent: they would be rejected and cost nothing useful.
            if ($trimmed) { $values.Add($trimmed) }
        }
    }

    end {
        if ($values.Count -eq 0) { return }

        if ($values.Count -eq 1) {
            $path = if ($type -eq 'name') { '/gender' } else { "/gender/$type" }
            $body = $options.Clone()
            $body[$type] = $values[0]
            Invoke-NameGenderApi -Path $path -ApiKey $key -Body $body
            return
        }

        for ($i = 0; $i -lt $values.Count; $i += $script:Chunk) {
            $body = $options.Clone()
            $body.names = @($values.GetRange($i, [Math]::Min($script:Chunk, $values.Count - $i)))
            $body.type = $type
            $response = Invoke-NameGenderApi -Path '/gender/bulk' -ApiKey $key -Body $body
            $response.results
        }
    }
}

function Get-NameGenderCountry {
    <#
    .SYNOPSIS
    Which countries a name is recorded in.

    .DESCRIPTION
    Not a country-of-origin or ethnicity inference. registrations is counted
    volume from the countries that publish counted birth statistics;
    attested_in is presence with no weight. Show basis.note next to any
    percentage. One credit per call.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)] [string] $Name,
        [ValidateRange(1, 100)] [int] $Limit = 25,
        [string] $ApiKey
    )

    $key = Resolve-NameGenderKey $ApiKey
    Invoke-NameGenderApi -Path '/gender/countries' -ApiKey $key -Body @{ name = $Name; limit = $Limit }
}

function Get-NameGenderAccount {
    <#
    .SYNOPSIS
    Credit balance and account status. Free: costs no credit.
    #>
    [CmdletBinding()]
    param([string] $ApiKey)

    $key = Resolve-NameGenderKey $ApiKey
    Invoke-NameGenderApi -Path '/me' -ApiKey $key -Method 'GET'
}

function Get-NameGenderSalutation {
    <#
    .SYNOPSIS
    Builds the salutation for a letter or email from full names.

    .DESCRIPTION
    One name calls the single endpoint; several names (from -Name or the
    pipeline) are sent in bulk requests of up to 100, and the results come
    back in input order. One credit per name. Each result carries the formal,
    informal and neutral salutation, plus form, reason, parts, gender and
    probability. When the gender is not certain the neutral form is used:
    form is 'neutral' and reason says why. -BestGuess does not apply here.

    With -Form, only that salutation text is returned, one string per name.

    .EXAMPLE
    Get-NameGenderSalutation 'Dr. Anna Müller' -Language de -Form formal

    .EXAMPLE
    Get-NameGenderSalutation -FirstName Ahmet -LastName Yılmaz -Language tr

    .EXAMPLE
    Get-Content names.txt | Get-NameGenderSalutation -Language de | Select-Object query, form, reason, @{ n = 'formal'; e = { $_.salutation.formal } }
    #>
    [CmdletBinding(DefaultParameterSetName = 'Name')]
    param(
        # Full name, titles included ("Dr. Anna Müller").
        [Parameter(ParameterSetName = 'Name', Mandatory, Position = 0, ValueFromPipeline)]
        [AllowEmptyString()]
        [string[]] $Name,

        # Instead of -Name, when the parts are stored separately. Not parsed.
        [Parameter(ParameterSetName = 'Parts')]
        [string] $FirstName,

        [Parameter(ParameterSetName = 'Parts')]
        [string] $LastName,

        # en, en-US, en-GB, de, de-AT, de-CH, fr, es, it, pt, pt-PT, pt-BR, nl, tr, pl, ja.
        # Default: the language of -Locale, else the main language of the country, else en.
        [string] $Language,

        # Country hint for the gender lookup, as in Get-NameGender.
        [ValidatePattern('^[A-Za-z]{2}$')]
        [string] $Country,

        [string] $Locale,

        [string] $Ip,

        # Known gender; skips the lookup. neutral always gives the neutral form.
        [ValidateSet('male', 'female', 'neutral')]
        [string] $Gender,

        # Below this probability the neutral form is used. API default: 90.
        [ValidateRange(50, 100)]
        [int] $MinProbability,

        # Academic title kept in a separate field, such as Dr.; used in de and en.
        [string] $Title,

        # Return only this salutation text instead of the whole result.
        [ValidateSet('formal', 'informal', 'neutral')]
        [string] $Form,

        [string] $ApiKey
    )

    begin {
        $key = Resolve-NameGenderKey $ApiKey
        $values = [System.Collections.Generic.List[string]]::new()
        $pick = $Form.ToLowerInvariant()

        # Only the options that were given are sent.
        $options = @{}
        if ($Language) { $options.language = $Language }
        if ($Country) { $options.country = $Country.ToUpperInvariant() }
        if ($Locale) { $options.locale = $Locale }
        if ($Ip) { $options.ip = $Ip }
        if ($Gender) { $options.gender = $Gender.ToLowerInvariant() }
        if ($PSBoundParameters.ContainsKey('MinProbability')) { $options.min_probability = $MinProbability }
        if ($Title) { $options.title = $Title }
    }

    process {
        foreach ($value in $Name) {
            $trimmed = "$value".Trim()
            # Blank lines are not sent.
            if ($trimmed) { $values.Add($trimmed) }
        }
    }

    end {
        $results = $null

        if ($PSCmdlet.ParameterSetName -eq 'Parts') {
            if (-not $FirstName -and -not $LastName) { throw 'Pass -FirstName, -LastName or both.' }
            $body = $options.Clone()
            if ($FirstName) { $body.first_name = $FirstName }
            if ($LastName) { $body.last_name = $LastName }
            $results = @(Invoke-NameGenderApi -Path '/salutation' -ApiKey $key -Body $body)
        } elseif ($values.Count -eq 0) {
            return
        } elseif ($values.Count -eq 1) {
            $body = $options.Clone()
            $body.name = $values[0]
            $results = @(Invoke-NameGenderApi -Path '/salutation' -ApiKey $key -Body $body)
        } else {
            $results = for ($i = 0; $i -lt $values.Count; $i += $script:Chunk) {
                $body = $options.Clone()
                $body.names = @($values.GetRange($i, [Math]::Min($script:Chunk, $values.Count - $i)))
                (Invoke-NameGenderApi -Path '/salutation/bulk' -ApiKey $key -Body $body).results
            }
        }

        foreach ($result in $results) {
            if ($pick) { $result.salutation.$pick } else { $result }
        }
    }
}

function Test-NameGenderName {
    <#
    .SYNOPSIS
    Says whether names typed into a form look like real people's names.

    .DESCRIPTION
    One name calls the single endpoint; several names (from -Name or the
    pipeline) are sent in bulk requests of up to 100, and the results come
    back in input order. One credit per name. Each result carries assessment
    (plausible, suspicious or implausible), score (0-100), signals (code,
    severity, part, value), first_name, last_name, name_type and evidence.

    It never calls a name fake: use it to flag records for a look, not to
    reject people automatically. Surnames are judged by their shape only.

    .EXAMPLE
    Test-NameGenderName 'asdf qwerty'

    .EXAMPLE
    Test-NameGenderName -FirstName Jennifer -LastName Null -Country US

    .EXAMPLE
    Import-Csv signups.csv | Select-Object -ExpandProperty FullName | Test-NameGenderName | Where-Object assessment -ne 'plausible'
    #>
    [CmdletBinding(DefaultParameterSetName = 'Name')]
    param(
        # Full name as typed ("Jennifer Null").
        [Parameter(ParameterSetName = 'Name', Mandatory, Position = 0, ValueFromPipeline)]
        [AllowEmptyString()]
        [string[]] $Name,

        # Instead of -Name, when the parts are stored separately. Not parsed.
        [Parameter(ParameterSetName = 'Parts')]
        [string] $FirstName,

        [Parameter(ParameterSetName = 'Parts')]
        [string] $LastName,

        # Country hint, as in Get-NameGender.
        [ValidatePattern('^[A-Za-z]{2}$')]
        [string] $Country,

        [string] $Locale,

        [string] $Ip,

        [string] $ApiKey
    )

    begin {
        $key = Resolve-NameGenderKey $ApiKey
        $values = [System.Collections.Generic.List[string]]::new()

        # Only the options that were given are sent.
        $options = @{}
        if ($Country) { $options.country = $Country.ToUpperInvariant() }
        if ($Locale) { $options.locale = $Locale }
        if ($Ip) { $options.ip = $Ip }
    }

    process {
        foreach ($value in $Name) {
            $trimmed = "$value".Trim()
            # Blank lines are not sent.
            if ($trimmed) { $values.Add($trimmed) }
        }
    }

    end {
        if ($PSCmdlet.ParameterSetName -eq 'Parts') {
            if (-not $FirstName -and -not $LastName) { throw 'Pass -FirstName, -LastName or both.' }
            $body = $options.Clone()
            if ($FirstName) { $body.first_name = $FirstName }
            if ($LastName) { $body.last_name = $LastName }
            Invoke-NameGenderApi -Path '/name-check' -ApiKey $key -Body $body
        } elseif ($values.Count -eq 0) {
            return
        } elseif ($values.Count -eq 1) {
            $body = $options.Clone()
            $body.name = $values[0]
            Invoke-NameGenderApi -Path '/name-check' -ApiKey $key -Body $body
        } else {
            for ($i = 0; $i -lt $values.Count; $i += $script:Chunk) {
                $body = $options.Clone()
                $body.names = @($values.GetRange($i, [Math]::Min($script:Chunk, $values.Count - $i)))
                (Invoke-NameGenderApi -Path '/name-check/bulk' -ApiKey $key -Body $body).results
            }
        }
    }
}

Export-ModuleMember -Function Get-NameGender, Get-NameGenderCountry, Get-NameGenderAccount, Get-NameGenderSalutation, Test-NameGenderName
