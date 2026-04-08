# 1. Ensure the airport database exists
$airportFile = "airports.csv"
$remoteUrl = "https://ourairports.com/data/airports.csv"

if (-not (Test-Path $airportFile)) { 
    Write-Host "[INFO] airports.csv not found. Downloading..." -ForegroundColor Cyan
    try {
        Start-BitsTransfer -Source $remoteUrl -Destination $airportFile -DisplayName "Downloading Airport Data"
    } catch {
        Write-Host "[ERROR] Failed to download database." -ForegroundColor Red; exit 
    }
}

Write-Host "[INFO] Loading airport database..." -ForegroundColor Gray

# Count lines reliably
$totalLines = (Get-Content $airportFile | Measure-Object -Line).Lines - 1
$interval = [Math]::Max(1, [int]($totalLines / 10))

# Initialize objects
$countryLookup = @{} 
$iataLookup    = @{} 
$i = 0

# Store the CSV data into an array so we can search it later
$airports = Import-Csv $airportFile | ForEach-Object {
    $i++
    if ($i % $interval -eq 0 -or $i -eq $totalLines) {
        $percent = [int](($i / $totalLines) * 100)
        Write-Progress -Activity "Loading Airport Database" -Status "$percent% Complete" -PercentComplete $percent
    }

    $icao = $_.gps_code
    if ($icao) { 
        $countryLookup[$icao] = $_.iso_country 
        $iataLookup[$icao]    = if ($_.iata_code) { $_.iata_code } else { $icao }
    }
    
    # This ensures the object is passed through to the $airports variable
    $_ 
}

Write-Progress -Activity "Loading Airport Database" -Completed
Write-Host "[SUCCESS] Loaded $($airports.Count) airports." -ForegroundColor Green

# 2. Flexible User Input
$userInput = (Read-Host "Enter Airport IATA or ICAO (e.g., PHX or KPHX)").ToUpper()
$originAirport = $airports | Where-Object { $_.gps_code -eq $userInput -or $_.iata_code -eq $userInput }

if (-not $originAirport) { Write-Host "[ERROR] Code not found!" -ForegroundColor Red; exit }

$targetIata    = if ($originAirport.iata_code) { $originAirport.iata_code } else { $originAirport.gps_code }
$targetCountry = $originAirport.iso_country 
$lat = [double]$originAirport.latitude_deg
$lon = [double]$originAirport.longitude_deg

Write-Host "`n[DEBUG] TARGET SET: $($originAirport.name) ($targetIata)" -ForegroundColor Cyan
Write-Host "[DEBUG] COORDINATES: $lat, $lon | COUNTRY: $targetCountry" -ForegroundColor Cyan

# 3. Processing Function with Commercial Filter
function Get-InternationalFlights {
    param($radiusNM, $minDistNM = 0)
    
    $results = New-Object System.Collections.Generic.List[PSCustomObject]
    $adsbUrl = "https://api.adsb.lol/v2/lat/$lat/lon/$lon/dist/$radiusNM"
    
    Write-Host "`n[DEBUG] Querying ADSB.lol (Radius: $radiusNM NM)..." -ForegroundColor Gray
    try {
        $liveData = Invoke-RestMethod -Uri $adsbUrl -Method Get -TimeoutSec 15
		
		if ($liveData.ac) {
			$totalFound = $liveData.ac.Count
		} else {
			$totalFound = 0
		}
		
        $planes = $liveData.ac | Where-Object { 
            $_.alt_baro -ne "ground" -and 
            $_.dst -ge $minDistNM -and 
            -not ([string]::IsNullOrWhiteSpace($_.flight)) 
        }
    } catch {
        Write-Host "[ERROR] ADSB.lol query failed: $($_.Exception.Message)" -ForegroundColor Red
        return $results
    }

	# --- SUMMARY SECTION ---
	$airbornePlanes = if ($liveData.ac) { 
		$liveData.ac | Where-Object { $_.alt_baro -ne "ground" } 
	} else { @() }

	$groundCount = $totalFound - $airbornePlanes.Count

	# Symmetrical Header
	Write-Host ("`n + " + ("=" * 40)) -ForegroundColor White
	Write-Host " AIRSPACE SUMMARY: $targetIata " -ForegroundColor White
	Write-Host (" + " + ("=" * 40)) -ForegroundColor White

	Write-Host " Total Aircraft Found : $totalFound"
	Write-Host " Airborne             : $($airbornePlanes.Count)" -ForegroundColor Cyan
	Write-Host " Ground/Static        : $groundCount" -ForegroundColor Gray

	if ($airbornePlanes.Count -gt 0) {
		# Count how many match our commercial Regex
		$commercial = $airbornePlanes | Where-Object { $_.flight -and $_.flight.Trim() -match '^[A-Z]{3}[0-9A-Z]{1,4}$' }
		Write-Host " Commercial Matches   : $($commercial.Count)" -ForegroundColor Green
		Write-Host " Private/Other        : $($airbornePlanes.Count - $commercial.Count)" -ForegroundColor DarkYellow
	}

	Write-Host (" + " + ("=" * 40)) -ForegroundColor White


    if ($null -eq $planes) { return $results }

	foreach ($plane in $planes)
	{
		$callsign = $plane.flight.Trim()
		
		# --- COMMERCIAL FILTER ---
		if ($callsign -match '^[A-Z]{3}[0-9][A-Z0-9]{0,3}$')
		{
			# Define distance inside the match block so it exists for the object later
			$distKm = [Math]::Round($plane.dst * 1.852, 1)
			Write-Host "[DEBUG] LOOKUP: $callsign ($distKm km)... " -NoNewline -ForegroundColor Gray
			
			try {
				$routeUrl = "https://api.adsbdb.com/v0/callsign/$callsign"
				$routeResp = Invoke-RestMethod -Uri $routeUrl -Method Get -UserAgent "Mozilla/5.0" -ErrorAction Stop
				$route = $routeResp.response.flightroute
				
				if ($route) {
					$originIcao = $route.origin.icao_code
					$destIcao   = $route.destination.icao_code
					
					$originIata = if ($iataLookup[$originIcao]) { $iataLookup[$originIcao] } else { $originIcao }
					$destIata   = if ($iataLookup[$destIcao])   { $iataLookup[$destIcao] }   else { $destIcao }
					$originCC = $countryLookup[$originIcao]; $destCC = $countryLookup[$destIcao]

					if (($originCC -and $originCC -ne $targetCountry) -or ($destCC -and $destCC -ne $targetCountry)) {
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
			
			# Sleep inside the match block to respect API rate limits only when calling it
			Start-Sleep -Milliseconds 200

		} else {
			# This 'else' now correctly pairs with the commercial filter 'if'
			Write-Host "[SKIP] $callsign (Non-Commercial)" -ForegroundColor DarkGray
		}
	}
    return $results
}

# --- INITIALIZATION ---
$finalResults = New-Object System.Collections.Generic.List[PSCustomObject]

# --- PRIMARY SEARCH (100km / 54NM) ---
$primaryResults = Get-InternationalFlights -radiusNM 54
if ($null -ne $primaryResults) {
    foreach ($r in $primaryResults) { $finalResults.Add($r) }
}

# --- CHECK FOR EXTENSION ---
if ($finalResults.Count -lt 2) {
    # Determine the correct phrasing
    $msg = if ($finalResults.Count -eq 0) { 
        "No international flights found within 100km." 
    } else { 
        "Only 1 international flight found within 100km." 
    }

    Write-Host "`n$msg" -ForegroundColor Cyan
    
    $choice = Read-Host "Would you like to extend search to 200km? (y/n)"
    if ($choice -eq 'y') {
        $extendedResults = Get-InternationalFlights -radiusNM 108 -minDistNM 54
        if ($null -ne $extendedResults) {
            foreach ($r in $extendedResults) { $finalResults.Add($r) }
        }
    }
}

# 5. Final Output
Write-Host ("`n" + ("=" * 70)) -ForegroundColor Cyan
Write-Host " INTERNATIONAL AIRBORNE FLIGHTS NEAR $targetIata " -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan

if ($finalResults.Count -gt 0) {
    $resultsDisplay = $finalResults | Sort-Object {[double]($_.Dist -replace ' km','')}
    $resultsDisplay | Format-Table -AutoSize
} else {
    Write-Host "No airborne international matches found." -ForegroundColor Yellow
}
