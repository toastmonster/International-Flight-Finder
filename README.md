# International-Flight-Finder 
A tool for finding international flights within 200km of any airport

**Project name**:  
International Flight Finder

**What does it do & how does it help SkyCards players?**  
When unlocking many airports for free travel one of the requirements is to catch 2 international flights. FlightRadar24 does not currently offer a filter capable of displaying this so I created this tool. It attempts to find all aircraft within 200km of your chosen airport, then filters them for any flights where the origin or destination airport's country differs from that of the chosen airport. It then offers an easy way to view each flight on FlightRadar24 for accurate positioning.

The tool is written in PowerShell and uses only free APIs, specifically:
* ourairports.com to get the location and details of your airport
* adsb.lol to find flights within the catchment area and return the origin and destination details

**Instructions on how to use**  
Download the attached PowerShell script. I will assume you save it to your default Downloads folder. Launch Windows PowerShell from your Start Menu. It will by default place you in your user profile home folder. To change to your Downloads folder type `cd Downloads` and press Enter. To launch the script, type `.\Find-InternationalFlights.ps1` and press Enter. 

If this is the first time running the script it will download the airports data file from ourairports.com and save it to the same folder.

It will prompt you to enter either the IATA (three characters) or ICAO (four characters) airport code. Type the airport code and press Enter. I will use `edi`.

> `Loading airports database...`  
> `  Loaded 85231 airports.`  
>  
> `Enter airport IATA or ICAO code (e.g. LHR or EGLL): edi`  

It will get the details of the airport you entered and will confirm the details on screen, including which country it's in, to compare with the flights it finds. It will then query the adsb.lol API to find aircraft within 200km of that airport.

> `Found airport:`  
> `  Name    : Edinburgh Airport`  
> `  ICAO    : EGPH`  
> `  IATA    : EDI`  
> `  Country : GB`  
> `  Location: 55.950145, -3.372288`  
> 
> `Step 1: Fetching aircraft within 200 km...`  
> `  Querying: https://api.adsb.lol/v2/lat/55.950145/lon/-3.372288/dist/108`  
> `  Found 41 aircraft.`  
> `  Aircraft data saved to: .\debug_aircraft_response.json`  

Next it will query the API to find the route information for every valid airborne aircraft within range. It will split the requests into batches of no more than 100 at a time.

> `Step 2: Fetching route information...`  
> `  37 aircraft to look up, sending in 1 chunk(s) of up to 100`  
> `  Chunk 1: OK, 37 routes returned`  
> `  Total routes received: 37`  
> `  Received route data for 37 aircraft.`  

Finally, it will display the 10 nearest international flights to your selected airport.

**Please note that this data isn't always accurate or up to date! I cannot be held responsible for incorrect flight information!**

Step 3: Filtering for international routes...

> `======================================================================`  
> ` International flights near Edinburgh Airport (EGPH) [GB]`  
> `======================================================================`  
>
> `Found 14 international aircraft. Showing 1-10:`  
>
> ` # Dist(km) Reg.   Callsign Type Origin              Destination`  
> ` - -------- ----   -------- ---- ------              -----------`  
> ` 1    22.50 LN-WEB WIF1JK   E290 DUB, Dublin, IE     BGO, Bergen, NO`  
> ` 2    40.00 PH-BQL KLM636   B772 LAS, Las Vegas, US  AMS, Amsterdam, NL`  
> ` 3    59.40 EI-GZV EAI2DM   AT76 GLA, Glasgow, GB    DUB, Dublin, IE`  
> ` 4    75.40 G-TUOA TOM84G   B38M BHX, Birmingham, GB BVC, Rabil, CV`  
> ` 5   103.30 TF-FIP ICE546   B752 KEF, Reykjavík, IS  CDG, Paris, FR`  
> ` 6   133.70 EI-HMX RYR6DP   B38M PSA, Pisa, IT       PIK, Glasgow, GB`  
> ` 7   136.80 TF-IAA ICE432   A21N KEF, Reykjavík, IS  GLA, Glasgow, GB`  
> ` 8   141.40 TF-ICN ICE2F    B38M KEF, Reykjavík, IS  FRA, Frankfurt-am-Main, DE`  
> ` 9   144.30 N660UA UAL947   B763 AMS, Amsterdam, NL  IAD, Washington, US`  
> `10   148.40 G-JZHN EXS8CL   B738 NCL, Newcastle, GB  LPA, Gran Canaria Island, ES`  
> 
>`Enter a number to open on FlightRadar24, M for more results, or Q to quit.`  

At this point you can enter a number to open the FlightRadar24 web page to view that flight, allowing you to easily pinpoint the aircraft within the Sky Cards game. You press M it will show you the next batch of results, and if you press Q it will quit the app.

**Current maintainers**  
@thetoastmonster
