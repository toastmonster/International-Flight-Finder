# International-Flight-Finder 
A tool for finding international flights within 100km of any airport

**Project name**:  
International Flight Finder

**What does it do & how does it help SkyCards players?**  
When unlocking many airports for free travel one of the requirements is to catch 2 international flights. FlightRadar24 does not currently offer a filter capable of displaying this so I created this tool. It attempts to find all commerical flights within 100km (standard catch circle radius) of your chosen airport, then filters them for any flights where the origin or destination airport's country differs from that of the chosen airport. If less than two international flights are found within 100km, it offers to extend the checking radius to 200km.

The tool is written in PowerShell and uses only free APIs, specifically:
* ourairports.com to get the location and details of your airport
* adsb.lol to find flights within the standard catchment area
* adsbdb.com to query each flight for its routing information
  * The query rate limits for this site are calculated over a rolling 60 second time period. 512 requests will see you blocked for 60 seconds. 1024 requests will see you blocked for 300 seconds. This is totally outside of my control.

**Instructions on how to use**  
Download the attached PowerShell script. I will assume you save it to your default Downloads folder. Launch Windows PowerShell from your Start Menu. It will by default place you in your user profile home folder. To change to your Downloads folder type `cd Downloads` and press Enter. To launch the script, type `.\find-international-flights.ps1` and press Enter. 

If this is the first time running the script it will download the airports data file from ourairports.com and save it to the same folder.

It will prompt you to enter either the IATA (three characters) or ICAO (four characters) airport code. Type the airport code and press Enter. I will use `cid`.

> `[INFO] airports.csv not found. Downloading...`  
> `[INFO] Loading airport database...`  
> `[SUCCESS] Loaded 85109 airports.`  
> `Enter Airport IATA or ICAO (e.g., PHX or KPHX): cid`  

It will get the details of the airport you entered and will confirm the details on screen, including which country it's in to compare with the flights it finds.

> `[DEBUG] TARGET SET: The Eastern Iowa Airport (CID)`  
> `[DEBUG] COORDINATES: 41.884701, -91.7108 | COUNTRY: US`  
> `[DEBUG] Querying ADSB.lol (Radius: 54 NM)...`  

It will give a summary of what aircraft it found within the catchment area, and filter out any that are on the ground or have callsigns that don't match the commercial flights pattern (three alpha characters followed by at least one number).

**Please note that the aircraft listed on adsb.lol aren't always the same as those listed on FlightRadar24 (and therefore in SkyCards), and I cannot be held responsible for inaccurate aircraft data!**

> `+ ========================================`  
> `AIRSPACE SUMMARY: CID`  
> `+ ========================================`  
> `Total Aircraft Found : 26`  
> `Airborne             : 25`  
> `Ground/Static        : 1`  
> `Commercial Matches   : 19`  
> `Private/Other        : 6`  
> `+ ========================================`  

Now because adsb.lol doesn't have origin or destination airport information for flights, the script will use the callsign for each flight to send a query to adsbdb.com to get that information. Flights that can't be found in their database return a (404) Not Found error.

**Please note that this data isn't always accurate or up to date! I cannot be held responsible for incorrect flight information!**

> `[SKIP] N1756W (Non-Commercial)`  
> `[SKIP] N919BW (Non-Commercial)`  
> `[DEBUG] LOOKUP: SWA103 (71.1 km)... DOMESTIC (PHL (US) -> MDW (US))`  
> `[DEBUG] LOOKUP: UAL2096 (71.8 km)... DOMESTIC (LAX (US) -> EWR (US))`  
> `[DEBUG] LOOKUP: DAL2825 (70.3 km)... DOMESTIC (ATL (US) -> MSP (US))`  
> `[DEBUG] LOOKUP: UAL2865 (82.1 km)... DOMESTIC (DEN (US) -> ORD (US))`  
> `[DEBUG] LOOKUP: UAL2368 (88.5 km)... DOMESTIC (SFO (US) -> DEN (US))`  
> `[DEBUG] LOOKUP: ENY3591 (78.4 km)... DOMESTIC (ORD (US) -> RDU (US))`  
> `[SKIP] N781AC (Non-Commercial)`  
> `[DEBUG] LOOKUP: ACA743 (85 km)... MATCH (Intl: LGA (US) -> YUL (CA))`  
> `[DEBUG] LOOKUP: LXJ597 (36.8 km)... ERR: Response status code does not indicate success: 404 (Not Found). (HTTP 404)`  
> `[SKIP] N310PG (Non-Commercial)`  
> `[DEBUG] LOOKUP: SKW4985 (6.1 km)... DOMESTIC (SJC (US) -> PHX (US))`  
> `[DEBUG] LOOKUP: ASA297 (81.8 km)... DOMESTIC (SAN (US) -> EWR (US))`  
> `[DEBUG] LOOKUP: ASA572 (19.4 km)... DOMESTIC (RDU (US) -> SEA (US))`  
> `[DEBUG] LOOKUP: UAL1830 (23.1 km)... DOMESTIC (SFO (US) -> BNA (US))`  
> `[DEBUG] LOOKUP: AAL2365 (93.7 km)... DOMESTIC (PHL (US) -> RSW (US))`  
> `[DEBUG] LOOKUP: AAY711 (47.6 km)... DOMESTIC (AZA (US) -> GEG (US))`  
> `[SKIP] N711LX (Non-Commercial)`  
> `[DEBUG] LOOKUP: AAL3147 (79.4 km)... DOMESTIC (LAX (US) -> ELP (US))`  
> `[DEBUG] LOOKUP: UAL3750 (79.1 km)... DOMESTIC (CLE (US) -> IAH (US))`  
> `[DEBUG] LOOKUP: DAL2247 (70.8 km)... DOMESTIC (DTW (US) -> MSN (US))`  
> `[DEBUG] LOOKUP: UAL219 (71.9 km)... DOMESTIC (ORD (US) -> HNL (US))`  
> `[DEBUG] LOOKUP: RPA3410 (98 km)... DOMESTIC (ORD (US) -> MSN (US))`  
> `[SKIP] N521BB (Non-Commercial)`  

Once the queries to adsbdb.com have finished the script will display details of any flight where the country of the origin or destination airport differs from that of your chosen airport, including the distance from the airport.

If less than two international flights were found, it will offer to extend the search radius to 200km (extended radar distance)

> `Only 1 international flight found within 100km.`  
> `Would you like to extend search to 200km? (y/n): y`  
> 
> `+ ========================================`  
> `AIRSPACE SUMMARY: CID`  
> `+ ========================================`  
> `Total Aircraft Found : 68`  
> `Airborne             : 64`  
> `Ground/Static        : 4`  
> `Commercial Matches   : 52`  
> `Private/Other        : 12`  
> `+ ========================================`
>   
> `[DEBUG] LOOKUP: DAL751 (196.3 km)... DOMESTIC (MSP (US) -> SEA (US))`  
> `[DEBUG] LOOKUP: DAL1188 (178.8 km)... DOMESTIC (CVG (US) -> MCO (US))`  
> `[DEBUG] LOOKUP: SWA1725 (166.7 km)... DOMESTIC (MDW (US) -> OAK (US))`  
> `[DEBUG] LOOKUP: UAL2200 (155.9 km)... DOMESTIC (EWR (US) -> SAN (US))`  
> `[DEBUG] LOOKUP: TWY718 (157.9 km)... ERR: Response status code does not indicate success: 404 (Not Found). (HTTP 404)`  
> `[DEBUG] LOOKUP: UAL1124 (166.8 km)... DOMESTIC (ORD (US) -> MSN (US))`  
> `[DEBUG] LOOKUP: UAL455 (190.4 km)... DOMESTIC (ORD (US) -> MSN (US))`  
> `[DEBUG] LOOKUP: SWA4215 (135.5 km)... DOMESTIC (SJC (US) -> BUR (US))`  
> `[SKIP] N209MG (Non-Commercial)`  
> `[DEBUG] LOOKUP: SWA2367 (122 km)... DOMESTIC (SFO (US) -> LAS (US))`  
> `[SKIP] N100RC (Non-Commercial)`  
> `[DEBUG] LOOKUP: SKW3989 (141.1 km)... DOMESTIC (PHX (US) -> LAX (US))`  
> `[DEBUG] LOOKUP: DAL2825 (114.4 km)... DOMESTIC (ATL (US) -> MSP (US))`  
> `[SKIP] N926JJ (Non-Commercial)`  
> `[DEBUG] LOOKUP: ENY3591 (118.2 km)... DOMESTIC (ORD (US) -> RDU (US))`  
> `[DEBUG] LOOKUP: CYO440 (167.3 km)... ERR: Response status code does not indicate success: 404 (Not Found). (HTTP 404)`  
> `[DEBUG] LOOKUP: ACA1048 (149 km)... MATCH (Intl: YVR (CA) -> ORD (US))`  
> `[DEBUG] LOOKUP: EJA188 (138.5 km)... DOMESTIC (MMU (US) -> BED (US))`  
> `[DEBUG] LOOKUP: AAL650 (149 km)... DOMESTIC (RDU (US) -> LGA (US))`  
> `[DEBUG] LOOKUP: AAY576 (119.4 km)... DOMESTIC (SFB (US) -> GRR (US))`  
> `[DEBUG] LOOKUP: PAT310 (197.3 km)... ERR: Response status code does not indicate success: 404 (Not Found). (HTTP 404)`  
> `[DEBUG] LOOKUP: WJA1361 (127.2 km)... MATCH (Intl: ATL (US) -> YWG (CA))`  
> `[DEBUG] LOOKUP: RPA3626 (134.1 km)... DOMESTIC (IAD (US) -> LGA (US))`  
> `[DEBUG] LOOKUP: AAL2365 (123.8 km)... DOMESTIC (PHL (US) -> RSW (US))`  
> `[DEBUG] LOOKUP: SKW3816 (176.5 km)... DOMESTIC (SEA (US) -> SFO (US))`  
> `[DEBUG] LOOKUP: UAL1877 (140.6 km)... DOMESTIC (IAH (US) -> EWR (US))`  
> `[DEBUG] LOOKUP: AAL3147 (127.6 km)... DOMESTIC (LAX (US) -> ELP (US))`  
> `[SKIP] N521BB (Non-Commercial)`  
> `[DEBUG] LOOKUP: RPA3410 (132.7 km)... DOMESTIC (ORD (US) -> MSN (US))`  
> `[SKIP] N336LS (Non-Commercial)`  
> `[DEBUG] LOOKUP: UAL1335 (140.8 km)... DOMESTIC (LGA (US) -> DEN (US))`  
> `[DEBUG] LOOKUP: SWA758 (196.3 km)... DOMESTIC (OAK (US) -> LAX (US))`  
> `[DEBUG] LOOKUP: AAL2765 (146.4 km)... DOMESTIC (ORD (US) -> PHX (US))`  
> `[DEBUG] LOOKUP: KAL036 (157.4 km)... MATCH (Intl: ATL (US) -> ICN (KR))`  
> `[DEBUG] LOOKUP: RPA4713 (169.1 km)... DOMESTIC (MSY (US) -> PHL (US))`  
> `[DEBUG] LOOKUP: SKW5664 (189.1 km)... DOMESTIC (ORD (US) -> MBS (US))`  
> `[DEBUG] LOOKUP: UAL1836 (194 km)... DOMESTIC (SEA (US) -> SFO (US))`  
> `[SKIP] HL8290 (Non-Commercial)`  
> `[DEBUG] LOOKUP: UAL1363 (184.5 km)... DOMESTIC (SJC (US) -> DEN (US))`  

You can now take the callsigns listed here and search for them in flightradar24.com to verify the information and see their current position, allowing you to quickly select the correct aircraft in SkyCards.

> `======================================================================`  
> ` INTERNATIONAL AIRBORNE FLIGHTS NEAR CID`  
> `======================================================================`  
> 
> `Callsign Type Origin   Dest     Dist       Alt`  
> `-------- ---- ------   ----     ----       ---`  
> `ACA743   C172 LGA (US) YUL (CA) 85 km    34000`  
> `WJA1361  B737 ATL (US) YWG (CA) 127.2 km 38000`  
> `ACA1048  A320 YVR (CA) ORD (US) 149 km   33025`  
> `KAL036   B77W ATL (US) ICN (KR) 157.4 km 30000`  

**Current maintainers**  
@thetoastmonster
