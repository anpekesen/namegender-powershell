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

Export-ModuleMember -Function Get-NameGender, Get-NameGenderCountry, Get-NameGenderAccount
