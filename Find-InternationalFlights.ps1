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
    Use -DebugMode switch to save API request/response JSON files for troubleshooting.
#>

param(
    [switch]$DebugMode
)

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

    if ($DebugMode) { $body | Set-Content -Path (Join-Path $DebugDir "debug_routeset_request_chunk$ChunkIndex.json") -Encoding UTF8 }

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

        if ($DebugMode) {
            $result | ConvertTo-Json -Depth 10 |
                Set-Content -Path (Join-Path $DebugDir "debug_routeset_response_chunk$ChunkIndex.json") -Encoding UTF8
        }
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
            if ($DebugMode) { $errBody | Set-Content -Path (Join-Path $DebugDir "debug_routeset_error_chunk$ChunkIndex.json") -Encoding UTF8 }
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
# Helper: remove debug JSON files created during the run
# ---------------------------------------------------------------------------
function Remove-DebugFiles {
    param([string]$Dir)
    if (-not $DebugMode) { return }
    $files = Get-ChildItem -Path $Dir -Filter 'debug_*.json' -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        Remove-Item -Path $f.FullName -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$csvPath   = Join-Path $scriptDir 'airports.csv'
$remoteUrl = "https://ourairports.com/data/airports.csv"
$debugDir  = $scriptDir

# Clean up any orphan debug files from a previous interrupted run
if ($DebugMode) {
    Remove-DebugFiles -Dir $debugDir
    Write-Host "Debug mode enabled. Files will be saved to: $debugDir" -ForegroundColor DarkGray
}

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

$changeAirport = $true

while ($changeAirport) {
    $changeAirport = $false

    Write-Host ""
    $inputCode = Read-Host "Enter airport IATA or ICAO code (e.g. LHR or EGLL)"

    if (-not $inputCode.Trim()) {
        Write-Error "No airport code entered."
        exit 1
    }

    $airport = Find-Airport -Code $inputCode -Airports $allAirports

    if (-not $airport) {
        Write-Host "Airport '$inputCode' not found in airports.csv. Please try again." -ForegroundColor Yellow
        $changeAirport = $true
        continue
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

# ---------------------------------------------------------------------------
# Fetch aircraft, get routes and filter to international flights.
# Returns a sorted list of international flight objects, or empty array.
# ---------------------------------------------------------------------------
function Get-InternationalFlights {
    param(
        [double]$Lat,
        [double]$Lon,
        [int]$RadiusKm,
        [string]$Country,
        [string]$DebugDir
    )

    # Step 1 - fetch nearby aircraft
    Write-Host "Step 1: Fetching aircraft within $RadiusKm km..." -ForegroundColor Cyan
    $nearbyAircraft = Get-AircraftNearPoint -Lat $Lat -Lon $Lon -RadiusKm $RadiusKm

    if (-not $nearbyAircraft -or $nearbyAircraft.Count -eq 0) {
        Write-Host "No aircraft found." -ForegroundColor Yellow
        return @()
    }

    Write-Host "  Found $($nearbyAircraft.Count) aircraft." -ForegroundColor DarkGray
    if ($DebugMode) {
        $nearbyAircraft | ConvertTo-Json -Depth 5 |
            Set-Content -Path (Join-Path $DebugDir 'debug_aircraft_response.json') -Encoding UTF8
        Write-Host "  Aircraft data saved to: $(Join-Path $DebugDir 'debug_aircraft_response.json')" -ForegroundColor DarkGray
    }
    Write-Host ""

    # Step 2 - fetch routes
    Write-Host "Step 2: Fetching route information..." -ForegroundColor Cyan
    $routes = @(Get-Routes -Aircraft $nearbyAircraft -DebugDir $DebugDir)

    if ($routes.Count -eq 0) {
        Write-Host "No route data returned. Check the debug files in: $DebugDir" -ForegroundColor Yellow
        return @()
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

    $results = New-Object System.Collections.Generic.List[object]

    foreach ($route in $routes) {

        if (-not $route.airport_codes -or $route.airport_codes -eq 'unknown') { continue }

        $routeAirports = $route._airports
        if (-not $routeAirports -or $routeAirports.Count -lt 2) { continue }

        $originAirport = $routeAirports[0]
        $destAirport   = $routeAirports[$routeAirports.Count - 1]

        $originCountry = $originAirport.countryiso2
        $destCountry   = $destAirport.countryiso2

        $originIsIntl = $originCountry -and ($originCountry.ToUpper() -ne $Country)
        $destIsIntl   = $destCountry   -and ($destCountry.ToUpper()   -ne $Country)

        if (-not $originIsIntl -and -not $destIsIntl) { continue }

        $ac  = $aircraftByCallsign[$route.callsign]
        $reg = Get-Prop $ac 'r'
        $typ = Get-Prop $ac 't'
        if (-not $reg) { $reg = '(unknown)' }
        if (-not $typ) { $typ = '' }

        $acLat = Get-Prop $ac 'lat'
        $acLon = Get-Prop $ac 'lon'
        if ($null -ne $acLat -and $null -ne $acLon) {
            $distKm = [math]::Round(
                (Get-DistanceKm -Lat1 $Lat -Lon1 $Lon -Lat2 $acLat -Lon2 $acLon),
                1
            )
        }
        else {
            $distKm = $null
        }

        $originLabel = "$($originAirport.iata), $($originAirport.location), $($originAirport.countryiso2)"
        $destLabel   = "$($destAirport.iata), $($destAirport.location), $($destAirport.countryiso2)"

        $results.Add(
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

    return @($results | Sort-Object -Property DistanceKm)
}

# ---------------------------------------------------------------------------
# Helper: display one page of results
# ---------------------------------------------------------------------------
function Show-Page {
    param([object[]]$Page, [int]$StartNumber)

    # Force $page to a true array so that IndexOf() and Format-Table work
    # correctly even when only a single result is passed in.
    $page = @($page)

    $page | Format-Table -AutoSize -Property @(
        @{ Label = '#';           Expression = { $StartNumber + [array]::IndexOf($page, $_) } },
        @{ Label = 'Dist(km)';    Expression = { $_.DistanceKm   } },
        @{ Label = 'Reg.';        Expression = { $_.Registration } },
        @{ Label = 'Callsign';    Expression = { $_.Callsign     } },
        @{ Label = 'Type';        Expression = { $_.Type         } },
        @{ Label = 'Origin';      Expression = { $_.Origin       } },
        @{ Label = 'Destination'; Expression = { $_.Destination  } }
    )
}

# ---------------------------------------------------------------------------
# Output loop — supports R to refresh, M for more pages, Q to quit
# ---------------------------------------------------------------------------

$doRefresh = $true

while ($doRefresh) {
    $doRefresh = $false

    Remove-DebugFiles -Dir $debugDir

    $sorted = @(Get-InternationalFlights `
        -Lat      $airportLat `
        -Lon      $airportLon `
        -RadiusKm 200 `
        -Country  $airportCountry `
        -DebugDir $debugDir)

    Write-Host ("=" * 70)
    Write-Host " International flights near $($airport.name) ($($airport.icao_code)) [$airportCountry]"
    Write-Host ("=" * 70)
    Write-Host ""

    if ($sorted.Count -eq 0) {
        Write-Host "No international flights found in the search results." -ForegroundColor Yellow
        Write-Host "R to refresh, C to change airport, or Q to quit." -ForegroundColor Cyan

        while ($true) {
            $userInput = (Read-Host "Choice").Trim()
            if ($userInput -eq '') { continue }

            if ($userInput -match '^[Qq]$') {
                Remove-DebugFiles -Dir $debugDir
                break
            }
            if ($userInput -match '^[Rr]$') {
                Write-Host ""
                Write-Host "Refreshing..." -ForegroundColor Cyan
                Write-Host ""
                $doRefresh = $true
                break
            }
            if ($userInput -match '^[Cc]$') {
                Remove-DebugFiles -Dir $debugDir
                $changeAirport = $true
                break
            }
            Write-Host "  Invalid input. Enter R to refresh, C to change airport, or Q to quit." -ForegroundColor Yellow
        }
        continue
    }

    $total     = $sorted.Count
    $pageSize  = 10
    $pageStart = 0

    $pageEnd     = [math]::Min($pageStart + $pageSize - 1, $total - 1)
    $currentPage = @($sorted[$pageStart..$pageEnd])
    $moreExist   = ($pageEnd -lt $total - 1)

    Write-Host "Found $total international aircraft. Showing 1-$($pageEnd + 1):" -ForegroundColor Green
    Write-Host ""
    Show-Page -Page $currentPage -StartNumber ($pageStart + 1)

    $userInput = ''

    while ($true) {
        $prompt = "Enter a number to open on FlightRadar24"
        if ($moreExist) { $prompt += ", M for more" }
        $prompt += ", R to refresh, C to change airport, or Q to quit"
        Write-Host $prompt -ForegroundColor Cyan

        $userInput = (Read-Host "Choice").Trim()

        if ($userInput -eq '') { continue }

        if ($userInput -match '^[Qq]$') {
            Remove-DebugFiles -Dir $debugDir
            break
        }

        if ($userInput -match '^[Rr]$') {
            Write-Host ""
            Write-Host "Refreshing..." -ForegroundColor Cyan
            Write-Host ""
            $doRefresh = $true
            break
        }

        if ($userInput -match '^[Cc]$') {
            Remove-DebugFiles -Dir $debugDir
            $doRefresh = $false
            $changeAirport = $true
            break
        }

        if ($moreExist -and $userInput -match '^[Mm]$') {
            $pageStart   = $pageStart + $pageSize
            $pageEnd     = [math]::Min($pageStart + $pageSize - 1, $total - 1)
            $currentPage = @($sorted[$pageStart..$pageEnd])
            $moreExist   = ($pageEnd -lt $total - 1)

            Write-Host ""
            Write-Host "Showing $($pageStart + 1)-$($pageEnd + 1) of $total" -ForegroundColor Green
            Write-Host ""
            Show-Page -Page $currentPage -StartNumber ($pageStart + 1)
            continue
        }

        if ($userInput -match '^\d+$') {
            $num = [int]$userInput
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

        $hint = if ($moreExist) { "a number, M for more, R to refresh, C to change airport, or Q to quit" } else { "a number, R to refresh, C to change airport, or Q to quit" }
        Write-Host "  Invalid input. Enter $hint." -ForegroundColor Yellow
    }

    # All pages exhausted via M with no Q/R — clean up and exit
    if (-not $doRefresh -and -not $changeAirport -and $userInput -notmatch '^[Qq]$' -and $userInput -notmatch '^[Rr]$') {
        if (-not $moreExist) {
            Write-Host ""
            Write-Host "All results shown." -ForegroundColor Green
            Remove-DebugFiles -Dir $debugDir
        }
    }
}

Write-Host ""
} # end while ($changeAirport)
