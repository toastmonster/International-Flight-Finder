# 1. Ensure the airport database exists
$airportFile = "airports.csv"
$remoteUrl = "https://ourairports.com/data/airports.csv"

if (-not (Test-Path $airportFile)) { 
    Write-Host "[INFO] airports.csv not found. Downloading latest global database..." -ForegroundColor Cyan
    try {
        # Using BITS for a reliable background transfer with a progress bar
        Start-BitsTransfer -Source $remoteUrl -Destination $airportFile -DisplayName "Downloading Airport Data"
        Write-Host "[SUCCESS] Database downloaded." -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Failed to download airport database: $($_.Exception.Message)" -ForegroundColor Red
        exit 
    }
}

# Import CSV and create lookups
$airports = Import-Csv $airportFile
$countryLookup = @{} # Key: ICAO (gps_code) -> Value: iso_country
$iataLookup    = @{} # Key: ICAO (gps_code) -> Value: iata_code
$nameLookup    = @{} # Key: ICAO (gps_code) -> Value: name

foreach ($row in $airports) { 
    $icao = $row.gps_code
    if ($icao) { 
        $countryLookup[$icao] = $row.iso_country 
        $iataLookup[$icao]    = if ($row.iata_code) { $row.iata_code } else { $icao }
        $nameLookup[$icao]    = $row.name
    } 
}

# 2. Flexible User Input (IATA or ICAO)
$userInput = (Read-Host "Enter Airport IATA or ICAO (e.g., PHX or KPHX)").ToUpper()
$originAirport = $airports | Where-Object { $_.gps_code -eq $userInput -or $_.iata_code -eq $userInput }

if (-not $originAirport) { 
    Write-Host "[ERROR] Code '$userInput' not found in your CSV database!" -ForegroundColor Red
    exit 
}

# Define core variables based on CSV headers
$targetIcao    = $originAirport.gps_code
$targetIata    = if ($originAirport.iata_code) { $originAirport.iata_code } else { $targetIcao }
$targetCountry = $originAirport.iso_country # CSV uses 2-letter code directly

# CSVs usually store coordinates as strings, so we ensure they are treated as decimals
$lat = [double]$originAirport.latitude_deg
$lon = [double]$originAirport.longitude_deg
$radiusNM = 54 # Approx 100km

Write-Host "`n[DEBUG] TARGET SET: $($originAirport.name) ($targetIata)" -ForegroundColor Cyan
Write-Host "[DEBUG] COORDINATES: $lat, $lon | COUNTRY: $targetCountry" -ForegroundColor Cyan

# 3. Query ADSB.lol
$adsbUrl = "https://api.adsb.lol/v2/lat/$lat/lon/$lon/dist/$radiusNM"
Write-Host "[DEBUG] Contacting ADSB.lol..." -ForegroundColor Gray

try {
    # Added -TimeoutSec 15 to prevent long hangs
    $liveData = Invoke-RestMethod -Uri $adsbUrl -Method Get -TimeoutSec 15
    
    # Check if the API returned a specific error message in the JSON
    if ($liveData.msg -and $liveData.msg -ne "No error") {
        Write-Host "[API WARNING] Server reported: $($liveData.msg)" -ForegroundColor Yellow
    }

    $totalFound = if ($liveData.ac) { $liveData.ac.Count } else { 0 }
} catch {
    $errorMessage = $_.Exception.Message
    if ($errorMessage -like "*timed out*") {
        Write-Host "[ERROR] Connection timed out. The server is likely busy." -ForegroundColor Red
    } else {
        Write-Host "[ERROR] Failed to contact ADSB.lol: $errorMessage" -ForegroundColor Red
    }
    # Exit or continue with 0 planes
    $totalFound = 0 
}

# --- SUMMARY SECTION ---
$airbornePlanes = $liveData.ac | Where-Object { $_.alt_baro -ne "ground" }
$groundCount = $totalFound - $airbornePlanes.Count

Write-Host ("`n" + ("=" * 40)) -ForegroundColor White
Write-Host " TOTAL AIRCRAFT DETECTED NEAR $targetIata : $totalFound " -ForegroundColor White
Write-Host " (Airborne: $($airbornePlanes.Count) | On Ground: $groundCount)" -ForegroundColor Gray
Write-Host (("=" * 40) + "`n") -ForegroundColor White

# 4. Process and Fetch International Routes
$results = New-Object System.Collections.Generic.List[PSCustomObject]

foreach ($plane in $airbornePlanes) {
    if ($null -eq $plane.flight -or [string]::IsNullOrWhiteSpace($plane.flight)) { continue }

    $callsign = $plane.flight.Trim()
    $distKm = [Math]::Round($plane.dst * 1.852, 1)

    $routeUrl = "https://api.adsbdb.com/v0/callsign/$callsign"
    Write-Host "[DEBUG] LOOKUP: $callsign ... " -NoNewline -ForegroundColor Gray
    
    try {
        $routeResp = Invoke-RestMethod -Uri $routeUrl -Method Get -UserAgent "Mozilla/5.0" -ErrorAction Stop
        $route = $routeResp.response.flightroute
        
        if ($route) {
            $originIcao = $route.origin.icao_code
            $destIcao   = $route.destination.icao_code
            
            $originIata = if ($iataLookup[$originIcao]) { $iataLookup[$originIcao] } else { $originIcao }
            $destIata   = if ($iataLookup[$destIcao])   { $iataLookup[$destIcao] }   else { $destIcao }

            # CSV Column iso_country is already 2 characters, so no truncate needed
            $originCC = $countryLookup[$originIcao]
            $destCC   = $countryLookup[$destIcao]

            $isOriginIntl = ($originCC -and $originCC -ne $targetCountry)
            $isDestIntl   = ($destCC -and $destCC -ne $targetCountry)

            if ($isOriginIntl -or $isDestIntl) {
                Write-Host "MATCH (Intl: $originIata ($originCC) -> $destIata ($destCC))" -ForegroundColor Green
                $results.Add([PSCustomObject]@{
                    Callsign = $callsign
                    Type     = if ($plane.t) { $plane.t } else { "???" }
                    Origin   = "$originIata ($originCC)"
                    Dest     = "$destIata ($destCC)"
                    Dist     = "$distKm km"
                    Alt      = $plane.alt_baro
                })
            } else { 
                Write-Host "DOMESTIC ($originIata ($originCC) -> $destIata ($destCC))" -ForegroundColor DarkYellow 
            }
        } else { 
            Write-Host "NOT IN DB" -ForegroundColor Yellow 
        }
    } catch { 
        $status = ""
        if ($_.Exception.Response) { $status = " (HTTP $([int]$_.Exception.Response.StatusCode))" }
        Write-Host "ERR: $($_.Exception.Message)$status" -ForegroundColor Red 
    }

    Start-Sleep -Milliseconds 200
}

# 5. Output Final Results
Write-Host ("`n" + ("=" * 70)) -ForegroundColor Cyan
Write-Host " INTERNATIONAL AIRBORNE FLIGHTS NEAR $targetIata " -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan

if ($results.Count -gt 0) {
    $results | Sort-Object {[double]($_.Dist -replace ' km','')} | Format-Table -AutoSize
} else {
    Write-Host "No airborne international matches found." -ForegroundColor Yellow
}