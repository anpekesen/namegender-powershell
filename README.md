# NameGender PowerShell

```powershell
Install-Module NameGender
$env:NAMEGENDER_API_KEY = 'ng_live_...'

Get-NameGender Andrea -Country IT
```

Windows PowerShell 5.1 and PowerShell 7 on Windows, macOS and Linux. No
dependencies. Get an API key from the [namegender.com](https://namegender.com)
dashboard.

## Names, emails and usernames

```powershell
Get-NameGender 'Ayşe Yılmaz'
Get-NameGender -Email jane.doe@example.com
Get-NameGender -Username jane_doe_92

# Many values: pipeline input is sent in bulk requests of up to 100
Get-Content names.txt | Get-NameGender | Export-Csv genders.csv -NoTypeInformation

Import-Csv customers.csv |
    Select-Object -ExpandProperty FirstName |
    Get-NameGender -Country DE |
    Select-Object query, gender, probability, sample_size
```

Every value costs one credit, unknown results included. Blank lines are
skipped and cost nothing.

## Options

| Parameter | Meaning |
|---|---|
| `-Country IT` | Two-letter country code. Andrea is male in Italy and female in Germany. |
| `-Locale it-IT` | Language tag; its region is the country when `-Country` is absent. `en` sets none. |
| `-Ip 93.42.0.1` | End user IP address; its country is used when neither of the above applies. Not stored. |
| `-BestGuess` | Return the more likely gender even when the evidence is weak. |
| `-ApiKey` | Overrides `$env:NAMEGENDER_API_KEY`. |

A result carries `query`, `name`, `first_name`, `middle_name`, `last_name`,
`name_type`, `gender`, `country`, `country_source`, `probability`,
`sample_size`, `took_ms`, `source`, `confidence` and `matched_as`. A single
lookup also returns `credits_charged`, `credits_remaining`, `data_version` and
`request_id`.

Errors are thrown with the API's reason code in the message and in
`$_.Exception.Data['error']` (for example `no_credits`, `invalid_key`), so a
script can branch on the code instead of the text:

```powershell
try { Get-NameGender Emma }
catch { if ($_.Exception.Data['error'] -eq 'no_credits') { ... } }
```

## Country distribution and account

```powershell
$dist = Get-NameGenderCountry Mehmet -Limit 10
$dist.registrations | Format-Table country, share, gender
$dist.basis.note

Get-NameGenderAccount   # credits remaining, free lookups today; costs nothing
```

`Get-NameGenderCountry` reports which countries a name is recorded in. It is
not a country-of-origin or ethnicity inference: `registrations` is counted
volume from the countries that publish counted birth statistics, and
`attested_in` is presence with no weight attached. Show `basis.note` next to
any percentage.

## License

MIT
