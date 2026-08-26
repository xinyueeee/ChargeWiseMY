param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'staging'),
    [ValidateRange(1, 1000)]
    [int]$PageSize = 1000
)

$ErrorActionPreference = 'Stop'

$layerUrl = 'https://gisdev.planmalaysia.gov.my/server/rest/services/Hosted/MEVnet_EVCB/FeatureServer/0'
$sourceUrl = $layerUrl

function Get-QueryString {
    param([hashtable]$Parameters)

    return ($Parameters.GetEnumerator() | ForEach-Object {
        '{0}={1}' -f [uri]::EscapeDataString([string]$_.Key),
            [uri]::EscapeDataString([string]$_.Value)
    }) -join '&'
}

function Get-NullableInteger {
    param($Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return 0
    }
    $parsed = 0
    if ([int]::TryParse(([string]$Value).Trim(), [ref]$parsed)) {
        return $parsed
    }
    return 0
}

function Get-NormalizedState {
    param([string]$State)

    $mapping = @{
        'JOHOR' = 'Johor'
        'KEDAH' = 'Kedah'
        'KELANTAN' = 'Kelantan'
        'MELAKA' = 'Melaka'
        'NEGERI SEMBILAN' = 'Negeri Sembilan'
        'PAHANG' = 'Pahang'
        'PERAK' = 'Perak'
        'PERLIS' = 'Perlis'
        'PULAU PINANG' = 'Penang'
        'SABAH' = 'Sabah'
        'SARAWAK' = 'Sarawak'
        'SELANGOR' = 'Selangor'
        'TERENGGANU' = 'Terengganu'
        'W.P. KUALA LUMPUR' = 'Kuala Lumpur'
        'W.P. LABUAN' = 'Labuan'
        'W.P. PUTRAJAYA' = 'Putrajaya'
    }
    $key = ([string]$State).Trim().ToUpperInvariant()
    if ($mapping.ContainsKey($key)) {
        return $mapping[$key]
    }
    return ([string]$State).Trim()
}

function Get-DeterministicStationId {
    param([int]$ObjectId)

    # Valid, stable UUID reserved for this import source. The final 12 hex
    # digits encode the MEVnet OBJECTID, making repeated exports idempotent.
    $suffix = $ObjectId.ToString('x12')
    return "6d65766e-6574-5000-8000-$suffix"
}

function Get-IsoDataDate {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }
    $parsed = [DateTime]::MinValue
    $culture = [Globalization.CultureInfo]::InvariantCulture
    if ([DateTime]::TryParseExact(
        $Value.Trim(),
        'd-MMM-yy',
        $culture,
        [Globalization.DateTimeStyles]::None,
        [ref]$parsed
    )) {
        return $parsed.ToString('yyyy-MM-dd')
    }
    return $null
}

function Test-ValidMalaysiaCoordinate {
    param($Latitude, $Longitude)

    if ($null -eq $Latitude -or $null -eq $Longitude) {
        return $false
    }
    $lat = [double]$Latitude
    $lon = [double]$Longitude
    return -not [double]::IsNaN($lat) -and -not [double]::IsInfinity($lat) -and
        -not [double]::IsNaN($lon) -and -not [double]::IsInfinity($lon) -and
        $lat -ge 0.5 -and $lat -le 7.6 -and
        $lon -ge 99.5 -and $lon -le 120.0
}

$metadata = Invoke-RestMethod -Uri "$layerUrl`?f=pjson"
$networkFields = @($metadata.fields | Where-Object {
    $_.alias -like 'Number of EV Charger by Network -*'
})

$features = [System.Collections.Generic.List[object]]::new()
$offset = 0
$pageNumber = 0

do {
    $pageNumber++
    $parameters = @{
        f = 'json'
        where = '1=1'
        outFields = '*'
        returnGeometry = 'false'
        orderByFields = 'objectid ASC'
        resultOffset = $offset
        resultRecordCount = $PageSize
    }
    $queryUrl = "$layerUrl/query?$(Get-QueryString $parameters)"
    $page = Invoke-RestMethod -Uri $queryUrl
    if ($null -ne $page.error) {
        throw ($page.error | ConvertTo-Json -Compress)
    }
    $pageFeatures = @($page.features)
    foreach ($feature in $pageFeatures) {
        $features.Add($feature)
    }
    $offset += $pageFeatures.Count
} while ($pageFeatures.Count -eq $PageSize)

$rawRows = @($features | ForEach-Object { $_.attributes })
$transformedRows = foreach ($row in $rawRows) {
    $validCoordinate = Test-ValidMalaysiaCoordinate $row.latitude $row.longitude
    $status = ([string]$row.status).Trim()
    $existingCount = Get-NullableInteger $row.number_of_existing_ev_charger_s
    $proposedCount = Get-NullableInteger $row.number_of_proposed_ev_charger__
    $acCount = Get-NullableInteger $row.type_ac
    $dcCount = Get-NullableInteger $row.type_dc
    $chargerType = if ($acCount -gt 0 -and $dcCount -gt 0) {
        'AC & DC Charger'
    } elseif ($dcCount -gt 0) {
        'DC Fast Charger'
    } elseif ($acCount -gt 0) {
        'AC Charger'
    } else {
        'Charger type not specified'
    }
    $networkCounts = [ordered]@{}
    foreach ($field in $networkFields) {
        $count = Get-NullableInteger $row.($field.name)
        if ($count -gt 0) {
            $networkName = ([string]$field.alias) -replace '^Number of EV Charger by Network -\s*', ''
            $networkCounts[$networkName] = $count
        }
    }
    $state = Get-NormalizedState ([string]$row.state)
    $networkCountsJson = if ($networkCounts.Count -eq 0) {
        '{}'
    } else {
        $networkCounts | ConvertTo-Json -Compress
    }

    [pscustomobject][ordered]@{
        station_id = Get-DeterministicStationId ([int]$row.objectid)
        station_name = ([string]$row.location).Trim()
        address = $null
        latitude = if ($null -eq $row.latitude) { $null } else { [double]$row.latitude }
        longitude = if ($null -eq $row.longitude) { $null } else { [double]$row.longitude }
        charger_type = $chargerType
        charger_count = $existingCount
        ac_charger_count = $acCount
        dc_charger_count = $dcCount
        status = $status
        indoor_outdoor = ([string]$row.indoor___outdoor).Trim()
        source = 'MEVnet / PLANMalaysia'
        mevnet_object_id = [int]$row.objectid
        source_url = $sourceUrl
        data_date = Get-IsoDataDate ([string]$row.data_as)
        source_data_date_original = ([string]$row.data_as).Trim()
        state = $state
        state_original = ([string]$row.state).Trim()
        pbt = ([string]$row.pbt).Trim()
        pbt_code = $row.pbt_code
        location = ([string]$row.location).Trim()
        existing_charger_count = $existingCount
        proposed_charger_count = $proposedCount
        ac_count = $acCount
        dc_count = $dcCount
        category = ([string]$row.category).Trim()
        indoor_count = Get-NullableInteger $row.indoor
        outdoor_count = Get-NullableInteger $row.outdoor
        network_counts = $networkCounts
        network_counts_json = $networkCountsJson
        coordinate_valid = $validCoordinate
        include_for_existing_coverage = ($status -eq 'Existing' -and $validCoordinate)
    }
}

$validRows = @($transformedRows | Where-Object { $_.coordinate_valid })
$duplicateGroups = @($validRows | Group-Object {
    '{0:R},{1:R}' -f [double]$_.latitude, [double]$_.longitude
} | Where-Object { $_.Count -gt 1 })

$statusSummary = @($transformedRows | Group-Object status | Sort-Object Name | ForEach-Object {
    [ordered]@{ status = $_.Name; count = $_.Count }
})
$stateSummary = @($transformedRows | Group-Object state | Sort-Object Name | ForEach-Object {
    $group = @($_.Group)
    [ordered]@{
        state = $_.Name
        total = $_.Count
        existing = @($group | Where-Object { $_.status -eq 'Existing' }).Count
        newly_proposed = @($group | Where-Object { $_.status -eq 'Newly Proposed' }).Count
    }
})

$summary = [ordered]@{
    generated_at_utc = [DateTime]::UtcNow.ToString('o')
    source = 'MEVnet'
    source_url = $sourceUrl
    source_max_record_count = [int]$metadata.maxRecordCount
    requested_page_size = $PageSize
    pages_retrieved = $pageNumber
    total_records = $transformedRows.Count
    status_counts = $statusSummary
    state_counts = $stateSummary
    valid_coordinate_records = $validRows.Count
    missing_coordinate_records = @($transformedRows | Where-Object {
        $null -eq $_.latitude -or $null -eq $_.longitude
    }).Count
    invalid_coordinate_records = @($transformedRows | Where-Object {
        $null -ne $_.latitude -and $null -ne $_.longitude -and -not $_.coordinate_valid
    }).Count
    missing_name_records = @($transformedRows | Where-Object {
        [string]::IsNullOrWhiteSpace($_.station_name)
    }).Count
    duplicate_coordinate_groups = $duplicateGroups.Count
    records_in_duplicate_coordinate_groups = ($duplicateGroups | Measure-Object Count -Sum).Sum
    existing_location_records_for_coverage = @($transformedRows | Where-Object {
        $_.include_for_existing_coverage
    }).Count
    existing_chargers_represented = ($transformedRows | Where-Object {
        $_.status -eq 'Existing'
    } | Measure-Object existing_charger_count -Sum).Sum
    proposed_chargers_represented = ($transformedRows | Measure-Object proposed_charger_count -Sum).Sum
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$rawRows | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'mevnet_raw.json') -Encoding utf8
$transformedRows | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'mevnet_staging.json') -Encoding utf8
$transformedRows | Select-Object station_id, station_name, address, latitude, longitude,
    charger_type, charger_count, ac_charger_count, dc_charger_count, status,
    indoor_outdoor, source, mevnet_object_id, source_url, data_date,
    source_data_date_original, state, state_original, pbt, pbt_code, location,
    proposed_charger_count, category, indoor_count, outdoor_count,
    network_counts_json, coordinate_valid, include_for_existing_coverage |
    Export-Csv -LiteralPath (Join-Path $OutputDirectory 'mevnet_staging.csv') -NoTypeInformation -Encoding utf8
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'mevnet_summary.json') -Encoding utf8

$summary | ConvertTo-Json -Depth 8
