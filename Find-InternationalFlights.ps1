#Requires -Version 5.1
<#
.SYNOPSIS
    Finds aircraft near an airport whose route crosses an international border.

.DESCRIPTION
    Prompts for an IATA or ICAO airport code, looks up its location in airports.csv
    (from ourairports.com, expected in the same directory as this script), then:
      1. Queries adsb.lol for all aircraft within 200 km of the airport.
      2. Queries adsb.lol for the route of every airborne aircraft with a callsign.
      3. Reports any aircraft whose origin OR destination country differs from the
         country of the airport you searched.

.NOTES
    Requires internet access to api.adsb.lol.
    airports.csv must be in the same directory as this script.
    Compatible with PowerShell 5.1 and PowerShell 7+.
#>

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Safe property accessor.
# Returns $null if the property does not exist on the object.
# Required because adsb.lol returns sparse objects where many properties
# are absent, and accessing a missing property throws under StrictMode.
# ---------------------------------------------------------------------------
function Get-Prop {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}

# ---------------------------------------------------------------------------
# Look up an airport by IATA or ICAO code
# ---------------------------------------------------------------------------
function Find-Airport {
    param([string]$Code, [object[]]$Airports)
    $upper = $Code.Trim().ToUpper()
    $match = $Airports | Where-Object { $_.icao_code -eq $upper } | Select-Object -First 1
    if (-not $match) {
        $match = $Airports | Where-Object { $_.iata_code -eq $upper } | Select-Object -First 1
    }
    return $match
}

# ---------------------------------------------------------------------------
# Haversine great-circle distance in km
# ---------------------------------------------------------------------------
function Get-DistanceKm {
    param([double]$Lat1, [double]$Lon1, [double]$Lat2, [double]$Lon2)
    $R    = 6371.0
    $dLat = ($Lat2 - $Lat1) * [math]::PI / 180
    $dLon = ($Lon2 - $Lon1) * [math]::PI / 180
    $a    = [math]::Sin($dLat / 2) * [math]::Sin($dLat / 2) +
            [math]::Cos($Lat1 * [math]::PI / 180) * [math]::Cos($Lat2 * [math]::PI / 180) *
            [math]::Sin($dLon / 2) * [math]::Sin($dLon / 2)
    return $R * 2 * [math]::Atan2([math]::Sqrt($a), [math]::Sqrt(1 - $a))
}

# ---------------------------------------------------------------------------
# Fetch all aircraft within $RadiusKm of a point
# ---------------------------------------------------------------------------
function Get-AircraftNearPoint {
    param([double]$Lat, [double]$Lon, [int]$RadiusKm)
    # v2 endpoint radius is in nautical miles; 1 km = 0.539957 NM
    $radiusNm = [math]::Round($RadiusKm * 0.539957)
    $url = "https://api.adsb.lol/v2/lat/$Lat/lon/$Lon/dist/$radiusNm"
    Write-Host "  Querying: $url" -ForegroundColor DarkGray
    try {
        $response = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 30
        return $response.ac
    }
    catch {
        Write-Warning "Failed to fetch aircraft data: $_"
        return @()
    }
}

# ---------------------------------------------------------------------------
# POST one chunk of planes to the routeset endpoint.
# Returns parsed results, or an empty array on failure.
# ---------------------------------------------------------------------------
function Invoke-RoutesetChunk {
    param([object[]]$Planes, [string]$DebugDir, [int]$ChunkIndex)

    $planesJson = $Planes | ConvertTo-Json -Depth 3
    if ($Planes.Count -eq 1) {
        $planesJson = '[' + $planesJson + ']'
    }
    $body = '{"planes":' + $planesJson + '}'

    $body | Set-Content -Path (Join-Path $DebugDir "debug_routeset_request_chunk$ChunkIndex.json") -Encoding UTF8

    try {
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)

        $headers = @{
            'Referer'    = 'https://adsb.lol/'
            'Origin'     = 'https://adsb.lol'
            'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'
        }

        $result = Invoke-RestMethod `
            -Uri 'https://api.adsb.lol/api/0/routeset' `
            -Method Post `
            -ContentType 'application/json; charset=utf-8' `
            -Headers $headers `
            -Body $bodyBytes `
            -TimeoutSec 60

        $result | ConvertTo-Json -Depth 10 |
            Set-Content -Path (Join-Path $DebugDir "debug_routeset_response_chunk$ChunkIndex.json") -Encoding UTF8
        Write-Host "  Chunk ${ChunkIndex}: OK, $(@($result).Count) routes returned" -ForegroundColor DarkGray
        return @($result)
    }
    catch {
        Write-Warning "  Chunk $ChunkIndex failed: $_"

        $errBody = $null
        try {
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                $errBody = $_.ErrorDetails.Message
            }
        }
        catch { }

        if ($errBody) {
            $errBody | Set-Content -Path (Join-Path $DebugDir "debug_routeset_error_chunk$ChunkIndex.json") -Encoding UTF8
            Write-Host "  Error body: $errBody" -ForegroundColor Red
        }
        return @()
    }
}

# ---------------------------------------------------------------------------
# Build the planes payload and send in chunks of up to $ChunkSize
# ---------------------------------------------------------------------------
function Get-Routes {
    param([object[]]$Aircraft, [string]$DebugDir, [int]$ChunkSize = 100)

    # Filter to airborne aircraft that have a callsign and a position
    $eligible = @(
        $Aircraft | Where-Object {
            $flight = Get-Prop $_ 'flight'
            $lat    = Get-Prop $_ 'lat'
            $lon    = Get-Prop $_ 'lon'
            $alt    = Get-Prop $_ 'alt_baro'
            ($null -ne $flight) -and ($flight.Trim() -ne '') -and
            ($null -ne $lat)    -and
            ($null -ne $lon)    -and
            ($alt -ne 'ground')
        }
    )

    if ($eligible.Count -eq 0) {
        Write-Host "  No airborne aircraft with callsigns found." -ForegroundColor Yellow
        return @()
    }

    # Build the full planes array
    $planes = @(
        $eligible | ForEach-Object {
            [ordered]@{
                callsign = (Get-Prop $_ 'flight').Trim()
                lat      = Get-Prop $_ 'lat'
                lng      = Get-Prop $_ 'lon'
            }
        }
    )

    $totalChunks = [math]::Ceiling($planes.Count / $ChunkSize)
    Write-Host "  $($planes.Count) aircraft to look up, sending in $totalChunks chunk(s) of up to $ChunkSize" -ForegroundColor DarkGray

    $allResults = New-Object System.Collections.Generic.List[object]

    for ($i = 0; $i -lt $totalChunks; $i++) {
        $start = $i * $ChunkSize
        $end   = [math]::Min($start + $ChunkSize - 1, $planes.Count - 1)
        $chunk = $planes[$start..$end]

        $chunkResults = Invoke-RoutesetChunk -Planes $chunk -DebugDir $DebugDir -ChunkIndex ($i + 1)
        foreach ($r in $chunkResults) {
            $allResults.Add($r)
        }

        if ($i -lt $totalChunks - 1) {
            Start-Sleep -Milliseconds 500
        }
    }

    Write-Host "  Total routes received: $($allResults.Count)" -ForegroundColor DarkGray
    return $allResults.ToArray()
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$csvPath   = Join-Path $scriptDir 'airports.csv'
$remoteUrl = "https://ourairports.com/data/airports.csv"
$debugDir  = $scriptDir

Write-Host "Debug files will be saved to: $debugDir" -ForegroundColor DarkGray

if (-not (Test-Path $csvPath)) {
    Write-Host "[INFO] airports.csv not found. Downloading..." -ForegroundColor Cyan
    try {
        Start-BitsTransfer -Source $remoteUrl -Destination $csvPath -DisplayName "Downloading Airport Data"
    } catch {
        Write-Host "[ERROR] Failed to download database." -ForegroundColor Red; exit 1
	}
}

Write-Host ""
Write-Host "Loading airports database..." -ForegroundColor Cyan
$allAirports = Import-Csv -Path $csvPath

Write-Host "  Loaded $($allAirports.Count) airports." -ForegroundColor DarkGray

Write-Host ""
$inputCode = Read-Host "Enter airport IATA or ICAO code (e.g. LHR or EGLL)"

if (-not $inputCode.Trim()) {
    Write-Error "No airport code entered."
    exit 1
}

$airport = Find-Airport -Code $inputCode -Airports $allAirports

if (-not $airport) {
    Write-Error "Airport '$inputCode' not found in airports.csv."
    exit 1
}

$airportCountry = $airport.iso_country.Trim().ToUpper()
$airportLat     = [double]$airport.latitude_deg
$airportLon     = [double]$airport.longitude_deg

Write-Host ""
Write-Host "Found airport:" -ForegroundColor Green
Write-Host "  Name    : $($airport.name)"
Write-Host "  ICAO    : $($airport.icao_code)"
Write-Host "  IATA    : $($airport.iata_code)"
Write-Host "  Country : $airportCountry"
Write-Host "  Location: $airportLat, $airportLon"
Write-Host ""

# Step 1 - fetch nearby aircraft
Write-Host "Step 1: Fetching aircraft within 200 km..." -ForegroundColor Cyan
$nearbyAircraft = Get-AircraftNearPoint -Lat $airportLat -Lon $airportLon -RadiusKm 200

if (-not $nearbyAircraft -or $nearbyAircraft.Count -eq 0) {
    Write-Host "No aircraft found near $($airport.name)." -ForegroundColor Yellow
    exit 0
}

Write-Host "  Found $($nearbyAircraft.Count) aircraft." -ForegroundColor DarkGray
$nearbyAircraft | ConvertTo-Json -Depth 5 |
    Set-Content -Path (Join-Path $debugDir 'debug_aircraft_response.json') -Encoding UTF8
Write-Host "  Aircraft data saved to: $(Join-Path $debugDir 'debug_aircraft_response.json')" -ForegroundColor DarkGray
Write-Host ""

# Step 2 - fetch routes
Write-Host "Step 2: Fetching route information..." -ForegroundColor Cyan
$routes = @(Get-Routes -Aircraft $nearbyAircraft -DebugDir $debugDir)

if ($routes.Count -eq 0) {
    Write-Host "No route data returned. Check the debug files in: $debugDir" -ForegroundColor Yellow
    exit 0
}

Write-Host "  Received route data for $($routes.Count) aircraft." -ForegroundColor DarkGray
Write-Host ""

# Build callsign -> aircraft lookup for registration, type and position
$aircraftByCallsign = @{}
foreach ($ac in $nearbyAircraft) {
    $flight = Get-Prop $ac 'flight'
    if ($flight -and $flight.Trim() -ne '') {
        $aircraftByCallsign[$flight.Trim()] = $ac
    }
}

# Step 3 - filter for international routes
Write-Host "Step 3: Filtering for international routes..." -ForegroundColor Cyan
Write-Host ""

$internationalFlights = New-Object System.Collections.Generic.List[object]

foreach ($route in $routes) {

    if (-not $route.airport_codes -or $route.airport_codes -eq 'unknown') { continue }

    $routeAirports = $route._airports
    if (-not $routeAirports -or $routeAirports.Count -lt 2) { continue }

    $originAirport = $routeAirports[0]
    $destAirport   = $routeAirports[$routeAirports.Count - 1]

    $originCountry = $originAirport.countryiso2
    $destCountry   = $destAirport.countryiso2

    $originIsIntl = $originCountry -and ($originCountry.ToUpper() -ne $airportCountry)
    $destIsIntl   = $destCountry   -and ($destCountry.ToUpper()   -ne $airportCountry)

    if (-not $originIsIntl -and -not $destIsIntl) { continue }

    # Aircraft registration and type
    $ac  = $aircraftByCallsign[$route.callsign]
    $reg = Get-Prop $ac 'r'
    $typ = Get-Prop $ac 't'
    if (-not $reg) { $reg = '(unknown)' }
    if (-not $typ) { $typ = '' }

    # Distance from the searched airport
    $acLat  = Get-Prop $ac 'lat'
    $acLon  = Get-Prop $ac 'lon'
    if ($null -ne $acLat -and $null -ne $acLon) {
        $distKm = [math]::Round(
            (Get-DistanceKm -Lat1 $airportLat -Lon1 $airportLon -Lat2 $acLat -Lon2 $acLon),
            1
        )
    }
    else {
        $distKm = $null
    }

    # Build labels directly from the API response fields
    $originLabel = "$($originAirport.iata), $($originAirport.location), $($originAirport.countryiso2)"
    $destLabel   = "$($destAirport.iata), $($destAirport.location), $($destAirport.countryiso2)"

    $internationalFlights.Add(
        [PSCustomObject]@{
            DistanceKm   = $distKm
            Registration = $reg
            Callsign     = $route.callsign
            Type         = $typ
            Origin       = $originLabel
            Destination  = $destLabel
        }
    )
}

# ---------------------------------------------------------------------------
# Helper: remove debug JSON files created during the run
# ---------------------------------------------------------------------------
function Remove-DebugFiles {
    param([string]$Dir)
    $files = Get-ChildItem -Path $Dir -Filter 'debug_*.json' -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        Remove-Item -Path $f.FullName -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Helper: display one page of results (10 rows) and return the page
# so the caller can reference rows by number
# ---------------------------------------------------------------------------
function Show-Page {
    param([object[]]$Page, [int]$StartNumber)

    $page | Format-Table -AutoSize -Property @(
        @{ Label = '#';           Expression = { $StartNumber + $page.IndexOf($_) } },
        @{ Label = 'Dist(km)';    Expression = { $_.DistanceKm   } },
        @{ Label = 'Reg.';        Expression = { $_.Registration } },
        @{ Label = 'Callsign';    Expression = { $_.Callsign     } },
        @{ Label = 'Type';        Expression = { $_.Type         } },
        @{ Label = 'Origin';      Expression = { $_.Origin       } },
        @{ Label = 'Destination'; Expression = { $_.Destination  } }
    )
}

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

Write-Host ("=" * 70)
Write-Host " International flights near $($airport.name) ($($airport.icao_code)) [$airportCountry]"
Write-Host ("=" * 70)
Write-Host ""

if ($internationalFlights.Count -eq 0) {
    Write-Host "No international flights found in the search results." -ForegroundColor Yellow
    Remove-DebugFiles -Dir $debugDir
}
else {
    # Sort all results once; paging works through this sorted array
    $sorted    = @($internationalFlights | Sort-Object -Property DistanceKm)
    $total     = $sorted.Count
    $pageSize  = 10
    $pageStart = 0   # index into $sorted of the first row on the current page

    # The rows visible on the current page (updated each time we show a page)
    $currentPage = @()

    # Show the first page
    $pageEnd     = [math]::Min($pageStart + $pageSize - 1, $total - 1)
    $currentPage = $sorted[$pageStart..$pageEnd]
    $moreExist   = ($pageEnd -lt $total - 1)

    Write-Host "Found $total international aircraft. Showing 1-$($pageEnd + 1):" -ForegroundColor Green
    Write-Host ""
    Show-Page -Page $currentPage -StartNumber ($pageStart + 1)

    # Prompt loop
    while ($true) {
        if ($moreExist) {
            Write-Host "Enter a number to open on FlightRadar24, M for more results, or Q to quit." -ForegroundColor Cyan
        }
        else {
            Write-Host "Enter a number to open on FlightRadar24, or Q to quit." -ForegroundColor Cyan
        }

        $userInput = (Read-Host "Choice").Trim()

        if ($userInput -eq '') { continue }

        if ($userInput -match '^[Qq]$') {
            Remove-DebugFiles -Dir $debugDir
            break
        }

        if ($moreExist -and $userInput -match '^[Mm]$') {
            # Advance to the next page
            $pageStart   = $pageStart + $pageSize
            $pageEnd     = [math]::Min($pageStart + $pageSize - 1, $total - 1)
            $currentPage = $sorted[$pageStart..$pageEnd]
            $moreExist   = ($pageEnd -lt $total - 1)

            Write-Host ""
            Write-Host "Showing $($pageStart + 1)-$($pageEnd + 1) of $total" -ForegroundColor Green
            Write-Host ""
            Show-Page -Page $currentPage -StartNumber ($pageStart + 1)
            continue
        }

        if ($userInput -match '^\d+$') {
            $num = [int]$userInput
            # Find the row with this display number anywhere in the sorted list
            $idx = $num - 1
            if ($idx -ge 0 -and $idx -lt $total) {
                $reg = $sorted[$idx].Registration
                $url = "https://www.flightradar24.com/$reg"
                Write-Host "  Opening $url ..." -ForegroundColor DarkGray
                Start-Process $url
            }
            else {
                Write-Host "  Please enter a number between 1 and $total." -ForegroundColor Yellow
            }
            continue
        }

        # If we reach here the input was not recognised
        if ($moreExist) {
            Write-Host "  Invalid input. Enter a number, M for more, or Q to quit." -ForegroundColor Yellow
        }
        else {
            Write-Host "  Invalid input. Enter a number or Q to quit." -ForegroundColor Yellow
        }
    }

    # If all pages were exhausted via M (no more results left), clean up and exit
    if (-not $moreExist -and $userInput -notmatch '^[Qq]$') {
        Write-Host ""
        Write-Host "All results shown." -ForegroundColor Green
        Remove-DebugFiles -Dir $debugDir
    }
}

Write-Host ""
