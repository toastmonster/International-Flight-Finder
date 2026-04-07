# International-Flight-Finder 
A tool for finding international flights within 100km of any airport

**Project name**:  
International Flight Finder

**What does it do & how does it help SkyCards players?**  
When unlocking many airports for free travel one of the requirements is to catch 2 international flights. FlightRadar24 does not currently offer a filter capable of displaying this so I created this tool. It attempts to find all flights within 100km (standard catch circle radius) of your chosen airport, then filters them for any flights where the origin or destination airport's country differs from that of the chosen airport.

The tool is written in PowerShell and uses only free APIs, specifically:
* ourairports.com to get the location and details of your airport
* adsb.lol to find flights within the standard catchment area
* adsbdb.com to query each flight for its routing information
  * The query rate limits for this site are calculated over a rolling 60 second time period. 512 requests will see you blocked for 60 seconds. 1024 requests will see you blocked for 300 seconds. This is totally outside of my control.

**Instructions on how to use**  
Download the attached PowerShell script. I will assume you save it to your default Downloads folder. Launch Windows PowerShell from your Start Menu. It will by default place you in your user profile home folder. To change to your Downloads folder type `cd Downloads` and press Enter. To launch the script, type `.\find-international-flights.ps1` and press Enter. 

If this is the first time running the script it will download the airports data file from ourairports.com and save it to the same folder.

It will prompt you to enter either the IATA (three characters) or ICAO (four characters) airport code. Type the airport code and press Enter. I will use `cgh`.

> `Enter Airport IATA or ICAO (e.g., PHX or KPHX): cgh`

It will get the details of the airport you entered and will confirm the details on screen, including which country it's in to compare with the flights it finds.

> `[DEBUG] TARGET SET: Congonhas–Deputado Freitas Nobre Airport (CGH)`  
> `[DEBUG] COORDINATES: -23.627657, -46.654601 | COUNTRY: BR`  
> `[DEBUG] Contacting ADSB.lol...`  

It will give a summary of what aircraft it found within the catchment area, and filter out any that are on the ground. **Please note that the aircraft listed on adsb.lol aren't always the same as those listed on FlightRadar24 (and therefore in SkyCards), and I cannot be held responsible for inaccurate aircraft data!**

> `========================================`  
> ` TOTAL AIRCRAFT DETECTED NEAR CGH : 32`  
> ` (Airborne: 26 | On Ground: 6)`  
> `========================================`

Now because adsb.lol doesn't have origin or destination airport information for flights, the script will use the callsign for each flight to send a query to adsbdb.com to get that information. Don't worry about the flights that return a 404 error, these are just the callsigns that aren't found. **Please note that this data isn't always accurate or up to date! I cannot be held responsible for incorrect flight information!**

> `[DEBUG] LOOKUP: TAM3415 ... DOMESTIC (POA (BR) -> GRU (BR))`  
> `[DEBUG] LOOKUP: LAN715 ... MATCH (Intl: MAD (ES) -> GRU (BR))`  
> `[DEBUG] LOOKUP: TAM3058 ... DOMESTIC (CGH (BR) -> CWB (BR))`  
> `[DEBUG] LOOKUP: GLO1545 ... DOMESTIC (CGR (BR) -> GRU (BR))`  
> `[DEBUG] LOOKUP: PSBNZ ... ERR: The remote server returned an error: (404) Not Found. (HTTP 404)`  
> `[DEBUG] LOOKUP: GLO1305 ... DOMESTIC (CNF (BR) -> CGH (BR))`  
> `[DEBUG] LOOKUP: TAM3687 ... DOMESTIC (SSA (BR) -> CGH (BR))`  
> `[DEBUG] LOOKUP: GLO1250 ... DOMESTIC (GRU (BR) -> FLN (BR))`  
> `[DEBUG] LOOKUP: PSBRX ... ERR: The remote server returned an error: (404) Not Found. (HTTP 404)`  
> `[DEBUG] LOOKUP: TAM3227 ... DOMESTIC (BPS (BR) -> GRU (BR))`  
> `[DEBUG] LOOKUP: TAM8192 ... MATCH (Intl: GRU (BR) -> AEP (AR))`  
> `[DEBUG] LOOKUP: PSKFA ... ERR: The remote server returned an error: (404) Not Found. (HTTP 404)`  
> `[DEBUG] LOOKUP: PPPML ... ERR: The remote server returned an error: (404) Not Found. (HTTP 404)`  
> `[DEBUG] LOOKUP: TAM3283 ... DOMESTIC (CWB (BR) -> GRU (BR))`  
> `[DEBUG] LOOKUP: AZU6030 ... DOMESTIC (CGH (BR) -> POA (BR))`  
> `[DEBUG] LOOKUP: N152D ... ERR: The remote server returned an error: (404) Not Found. (HTTP 404)`  
> `[DEBUG] LOOKUP: PSDYB ... ERR: The remote server returned an error: (404) Not Found. (HTTP 404)`  
> `[DEBUG] LOOKUP: PSDRC ... ERR: The remote server returned an error: (404) Not Found. (HTTP 404)`  
> `[DEBUG] LOOKUP: GLO1355 ... DOMESTIC (SJP (BR) -> CGH (BR))`  
> `[DEBUG] LOOKUP: AAL995 ... MATCH (Intl: MIA (US) -> GRU (BR))`  
> `[DEBUG] LOOKUP: PTYML ... ERR: The remote server returned an error: (404) Not Found. (HTTP 404)`  
> `[DEBUG] LOOKUP: GLO1481 ... DOMESTIC (CGR (BR) -> GRU (BR))`  
> `[DEBUG] LOOKUP: GLO1271 ... DOMESTIC (XAP (BR) -> CGH (BR))`  
> `[DEBUG] LOOKUP: GLO1241 ... DOMESTIC (MGF (BR) -> GRU (BR))`  
> `[DEBUG] LOOKUP: TAM4676 ... DOMESTIC (GRU (BR) -> BSB (BR))`  
> `[DEBUG] LOOKUP: TAM3020 ... DOMESTIC (GRU (BR) -> FOR (BR))`  

Once the queries to adsbdb.com have finished the script will display details of any flight where the country of the origin or destination airport differs from that of your chosen airport, including the distance from the airport. You can now take the callsigns listed here and search for them in flightradar24.com to verify the information and see their current position, allowing you to quickly select the correct aircraft in SkyCards.

> `======================================================================`  
> ` INTERNATIONAL AIRBORNE FLIGHTS NEAR CGH`  
> `======================================================================`  
>   
> `Callsign Type Origin   Dest     Dist      Alt`  
> `-------- ---- ------   ----     ----      ---`  
> `AAL995   B788 MIA (US) GRU (BR) 18.6 km  5000`  
> `TAM8192  A20N GRU (BR) AEP (AR) 53.5 km 25100`  
> `LAN715   B788 MAD (ES) GRU (BR) 72.1 km 27375`  

**Current maintainers**  
@thetoastmonster
