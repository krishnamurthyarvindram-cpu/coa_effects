# COA Master Dataset — Coverage & Missingness Report

**Master dataset:** `merged_data/coa_master_panel.csv` (also `.rds`)  
**Rows:** 11760 (city-years)  
**Cities:** 336 unique COA cities  
**Years:** 1990 to 2024  
**Treated (has COA):** 123  ·  Never-treated: 213  

## What's in it

| Block | Source file | Key | Year span |
|---|---|---|---|
| COA treatment + powers | `coa_creation_data.csv` | city + state | static |
| Arrests by race x offense, LEMAS officers, demshare, chief identity, CoG spending, demographics | `data_panel_post1990.rds` | place_fips x year | 1990-2021 |
| Fiscal: police/total/social spending, poverty, unemployment, race shares | `Austerity.dta` | place_fips x year | 1990-2019 |
| Demographics (race/gender %) | `cities_historical_demographics.rds` | place_fips x year | 1970-2020 |
| Police employees (officers, civilians, total) | `ucrPoliceEmployeeData.csv` | place_fips x year | 2008-2019 |
| Police killings | `cleaned_data/police_killings.rds` (from MPV xlsx) | city + state x year | 1999-2021 |
| Presidential Dem vote share | `demVoteShareAllYearsFIPS.csv` | county_fips x year | 2000-2020 |
| County council composition | `countycouncils_comp.rds` | county_fips x year | 1989-2021 |

## Crosswalk match rates (336 COA cities -> external IDs)

| Crosswalk source | COA cities matched (of 336) |
|---|---|
| UCR panel (place_fips)             | 283 (84.2%) |
| Austerity (place_fips)             | 274 (81.5%) |
| city_data.tab (place_fips)         | 276 (82.1%) |
| LEOKA employee data (place_fips)   | 286 (85.1%) |
| **ANY place_fips resolved**        | **315 (93.8%)** |
| County FIPS resolved               | 306 (91.1%) |
| ORI9 (police agency ID) resolved   | 306 (91.1%) |

## Coverage by variable block

Two windows shown:
- **1990-2021** (the dense panel period)
- **2000-2021** (when MPV/vote share/most council data starts)

*Cities w/ data* = COA cities with at least one non-missing observation in any year of the window.  
*City-yr % filled* = share of (city × year) cells in the window with at least one non-missing variable in the block.

| Variable block | Cities w/ data 1990-21 (% of 336) | City-yr % filled 1990-21 | Cities w/ data 2000-21 (%) | City-yr % filled 2000-21 |
|---|---|---|---|---|
| UCR arrests by race x offense | 321 (95.5%) | 75.2% | 290 (86.3%) | 74.6% |
| UCR reporting completeness (months) | 321 (95.5%) | 75.2% | 290 (86.3%) | 74.6% |
| Police killings (Mapping Police Violence) | 328 (97.6%) | 38.2% | 328 (97.6%) | 55.5% |
| Police employees / officers (LEOKA, 2008-2019) | 290 (86.3%) | 30.8% | 290 (86.3%) | 44.7% |
| Police officers race/gender (LEMAS) | 273 (81.2%) | 73.5% | 271 (80.7%) | 75.3% |
| Police FTEs (Census of Governments) | 279 (83.0%) | 67.4% | 277 (82.4%) | 72.7% |
| Police spending per capita | 307 (91.4%) | 82.3% | 307 (91.4%) | 79.4% |
| Total municipal spending / revenue | 307 (91.4%) | 82.0% | 307 (91.4%) | 79.1% |
| City racial/gender demographics | 308 (91.7%) | 88.8% | 308 (91.7%) | 87.5% |
| City economic (poverty, unemp, race shares) | 279 (83.0%) | 79.7% | 279 (83.0%) | 78.9% |
| Presidential Dem vote share (county-level) | 319 (94.9%) | 64.5% | 319 (94.9%) | 93.8% |
| City Dem/Rep in power (mayor/council from panel) | 284 (84.5%) | 82.5% | 284 (84.5%) | 81.6% |
| County council composition (party/race/gender) | 269 (80.1%) | 22.6% | 265 (78.9%) | 28.5% |
| Police chief identity (race/gender) | 276 (82.1%) | 36.2% | 276 (82.1%) | 52.6% |

## Year-by-year coverage (% of 336 COA cities with non-missing) — selected variables

| Variable | 1990 | 1992 | 1994 | 1996 | 1998 | 2000 | 2002 | 2004 | 2006 | 2008 | 2010 | 2012 | 2014 | 2016 | 2018 | 2020 | 2022 | 2024 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| UCR arrests (any race/offense) | 81 | 84 | 81 | 70 | 71 | 72 | 74 | 73 | 77 | 79 | 79 | 80 | 81 | 82 | 83 | 79 | 11 | 9 |
| UCR months reported | 81 | 84 | 81 | 70 | 71 | 72 | 74 | 73 | 77 | 79 | 79 | 80 | 81 | 82 | 83 | 79 | 11 | 9 |
| Police killings (MPV) | 0 | 0 | 0 | 0 | 0 | 42 | 46 | 46 | 54 | 53 | 52 | 59 | 58 | 63 | 63 | 67 | 0 | 0 |
| Total officers (LEOKA) | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 85 | 85 | 83 | 78 | 82 | 81 | 0 | 0 | 0 |
| Sworn officers (LEMAS) | 60 | 60 | 72 | 72 | 76 | 76 | 76 | 78 | 78 | 79 | 79 | 79 | 80 | 79 | 79 | 70 | 0 | 0 |
| Police FTEs (Census) | 0 | 82 | 79 | 0 | 79 | 79 | 64 | 59 | 58 | 82 | 82 | 82 | 79 | 79 | 79 | 79 | 0 | 0 |
| Police $ per capita (CoG) | 84 | 80 | 81 | 81 | 81 | 82 | 84 | 83 | 83 | 83 | 84 | 84 | 77 | 76 | 77 | 0 | 0 | 0 |
| Police $ per capita (Austerity) | 82 | 82 | 81 | 81 | 81 | 82 | 82 | 82 | 82 | 82 | 82 | 82 | 72 | 72 | 72 | 0 | 0 | 0 |
| Total municipal $ per capita | 82 | 82 | 81 | 81 | 81 | 82 | 82 | 82 | 82 | 82 | 82 | 82 | 72 | 72 | 72 | 0 | 0 | 0 |
| City % white | 92 | 92 | 92 | 92 | 92 | 92 | 92 | 92 | 92 | 92 | 92 | 92 | 92 | 92 | 92 | 92 | 0 | 0 |
| Pres Dem vote share (county) | 0 | 0 | 0 | 0 | 0 | 86 | 86 | 86 | 86 | 86 | 86 | 95 | 95 | 95 | 95 | 82 | 0 | 0 |
| County council size | 4 | 15 | 17 | 18 | 30 | 36 | 43 | 44 | 42 | 47 | 47 | 47 | 49 | 53 | 64 | 70 | 0 | 0 |
| Police chief race | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 78 | 80 | 81 | 81 | 80 | 80 | 80 | 0 | 0 |

## COA cities with NO data in a given block (1990-2021)

These are typically (a) census-designated places without their own police agency or (b) cities not in the source panel.

### UCR arrests by race x offense — 15 cities missing entirely

-  brandon_fl
- columbia_md
- east los angeles_ca
- enterprise_nv
- highlands ranch_co
- lehigh acres_fl
- metairie_la
- paradise_nv
- riverview_fl
- san tan valley_az
- south fulton_ga
- spring hill_fl
- spring valley_nv
- sunrise manor_nv
- the woodlands_tx

### UCR reporting completeness (months) — 15 cities missing entirely

-  brandon_fl
- columbia_md
- east los angeles_ca
- enterprise_nv
- highlands ranch_co
- lehigh acres_fl
- metairie_la
- paradise_nv
- riverview_fl
- san tan valley_az
- south fulton_ga
- spring hill_fl
- spring valley_nv
- sunrise manor_nv
- the woodlands_tx

### Police killings (Mapping Police Violence) — 8 cities missing entirely

-  athens clarke county_ga
- augusta richmond county_ga
- highlands ranch_co
- lexington fayette urban county_ky
- nashville davidson county_tn
- paradise_nv
- san buenaventura_ca
- sunrise manor_nv

### Police employees / officers (LEOKA, 2008-2019) — 46 cities missing entirely

-  arlington_va
- augusta richmond county_ga
- brandon_fl
- centennial_co
- chico_ca
- columbia_md
- concord_nc
- east los angeles_ca
- enterprise_nv
- highlands ranch_co
- honolulu_hi
- jurupa valley_ca
- lancaster_ca
- lehigh acres_fl
- louisville_ky
- macon_ga
- menifee_ca
- meridian_id
- metairie_la
- miami gardens_fl
- moreno valley_ca
- murrieta_ca
- norwalk_ca
- palmdale_ca
- paradise_nv
- pompano beach_fl
- quincy_ma
- rancho cucamonga_ca
- richmond_va
- riverview_fl
- roseville_ca
- san tan valley_az
- santa clarita_ca
- south fulton_ga
- spokane valley_wa
- spring hill_fl
- spring valley_nv
- sugar land_tx
- sunrise manor_nv
- temecula_ca
- the woodlands_tx
- thousand oaks_ca
- tuscaloosa_al
- vacaville_ca
- victorville_ca
- winston salem_nc

### Police officers race/gender (LEMAS) — 63 cities missing entirely

-  arlington_va
- athens clarke county_ga
- augusta richmond county_ga
- baton rouge_la
- brandon_fl
- broken arrow_ok
- burbank_ca
- cambridge_ma
- centennial_co
- chico_ca
- clovis_ca
- columbia_md
- columbus_ga
- concord_ca
- corona_ca
- daly_ca
- downey_ca
- east los angeles_ca
- enterprise_nv
- fullerton_ca
- glendale_ca
- highlands ranch_co
- honolulu_hi
- huntington beach_ca
- indianapolis_in
- jacksonville_fl
- jurupa valley_ca
- lancaster_ca
- las vegas_nv
- lehigh acres_fl
- lexington fayette urban county_ky
- lowell_ma
- macon_ga
- menifee_ca
- metairie_la
- miami gardens_fl
- moreno valley_ca
- murrieta_ca
- norwalk_ca
- palmdale_ca
- paradise_nv
- rancho cucamonga_ca
- riverview_fl
- roseville_ca
- san buenaventura_ca
- san mateo_ca
- san tan valley_az
- sandy springs_ga
- santa clarita_ca
- santa rosa_ca
- south fulton_ga
- spokane valley_wa
- spring hill_fl
- spring valley_nv
- sugar land_tx
- sunrise manor_nv
- temecula_ca
- the woodlands_tx
- thousand oaks_ca
- victorville_ca
- visalia_ca
- west covina_ca
- wichita falls_tx

### Police FTEs (Census of Governments) — 57 cities missing entirely

-  arlington_va
- athens clarke county_ga
- augusta richmond county_ga
- brandon_fl
- broken arrow_ok
- burbank_ca
- cambridge_ma
- centennial_co
- chico_ca
- clovis_ca
- columbia_md
- concord_ca
- corona_ca
- daly_ca
- downey_ca
- east los angeles_ca
- enterprise_nv
- fullerton_ca
- glendale_ca
- highlands ranch_co
- honolulu_hi
- huntington beach_ca
- indianapolis_in
- jurupa valley_ca
- lehigh acres_fl
- lowell_ma
- macon_ga
- menifee_ca
- metairie_la
- miami gardens_fl
- moreno valley_ca
- murrieta_ca
- nashville davidson county_tn
- norwalk_ca
- palmdale_ca
- paradise_nv
- riverview_fl
- roseville_ca
- san buenaventura_ca
- san mateo_ca
- san tan valley_az
- sandy springs_ga
- santa clarita_ca
- santa rosa_ca
- south fulton_ga
- spokane valley_wa
- spring hill_fl
- spring valley_nv
- sugar land_tx
- sunrise manor_nv
- temecula_ca
- the woodlands_tx
- thousand oaks_ca
- victorville_ca
- visalia_ca
- west covina_ca
- wichita falls_tx

### Police spending per capita — 29 cities missing entirely

-  arlington_va
- athens clarke county_ga
- brandon_fl
- centennial_co
- chico_ca
- columbia_md
- east los angeles_ca
- enterprise_nv
- highlands ranch_co
- honolulu_hi
- jurupa valley_ca
- lehigh acres_fl
- menifee_ca
- metairie_la
- miami gardens_fl
- murrieta_ca
- paradise_nv
- riverview_fl
- roseville_ca
- san tan valley_az
- south fulton_ga
- spokane valley_wa
- spring hill_fl
- spring valley_nv
- sugar land_tx
- sunrise manor_nv
- temecula_ca
- the woodlands_tx
- victorville_ca

### Total municipal spending / revenue — 29 cities missing entirely

-  arlington_va
- athens clarke county_ga
- brandon_fl
- centennial_co
- chico_ca
- columbia_md
- east los angeles_ca
- enterprise_nv
- highlands ranch_co
- honolulu_hi
- jurupa valley_ca
- lehigh acres_fl
- menifee_ca
- metairie_la
- miami gardens_fl
- murrieta_ca
- paradise_nv
- riverview_fl
- roseville_ca
- san tan valley_az
- south fulton_ga
- spokane valley_wa
- spring hill_fl
- spring valley_nv
- sugar land_tx
- sunrise manor_nv
- temecula_ca
- the woodlands_tx
- victorville_ca

### City racial/gender demographics — 28 cities missing entirely

-  arlington_va
- brandon_fl
- centennial_co
- chico_ca
- columbia_md
- east los angeles_ca
- enterprise_nv
- highlands ranch_co
- honolulu_hi
- jurupa valley_ca
- lehigh acres_fl
- menifee_ca
- metairie_la
- miami gardens_fl
- murrieta_ca
- paradise_nv
- riverview_fl
- roseville_ca
- san tan valley_az
- south fulton_ga
- spokane valley_wa
- spring hill_fl
- spring valley_nv
- sugar land_tx
- sunrise manor_nv
- temecula_ca
- the woodlands_tx
- victorville_ca

### City economic (poverty, unemp, race shares) — 57 cities missing entirely

-  allen_tx
- arlington_va
- athens clarke county_ga
- augusta richmond county_ga
- brandon_fl
- cary_nc
- centennial_co
- chico_ca
- columbia_md
- columbus_ga
- concord_nc
- davie_fl
- east los angeles_ca
- edinburg_tx
- elk grove_ca
- enterprise_nv
- frisco_tx
- gilbert_az
- highlands ranch_co
- hillsboro_or
- honolulu_hi
- jurupa valley_ca
- kent_wa
- league_tx
- lee s summit_mo
- lehigh acres_fl
- lewisville_tx
- mckinney_tx
- menifee_ca
- meridian_id
- metairie_la
- miami gardens_fl
- miramar_fl
- murfreesboro_tn
- murrieta_ca
- nampa_id
- north las vegas_nv
- paradise_nv
- pearland_tx
- renton_wa
- rio rancho_nm
- riverview_fl
- roseville_ca
- round rock_tx
- san tan valley_az
- south fulton_ga
- spokane valley_wa
- spring hill_fl
- spring valley_nv
- sugar land_tx
- sunrise manor_nv
- surprise_az
- temecula_ca
- the woodlands_tx
- vancouver_wa
- victorville_ca
- west jordan_ut

### Presidential Dem vote share (county-level) — 17 cities missing entirely

-  athens clarke county_ga
- augusta richmond county_ga
- brockton_ma
- charlotte_nc
- concord_nc
- elk grove_ca
- las vegas_nv
- louisville_ky
- north las vegas_nv
- philadelphia_pa
- quincy_ma
- richmond_va
- savannah_ga
- south bend_in
- tuscaloosa_al
- winston salem_nc
- worcester_ma

### City Dem/Rep in power (mayor/council from panel) — 52 cities missing entirely

-  arlington_va
- brandon_fl
- broken arrow_ok
- burbank_ca
- cambridge_ma
- centennial_co
- chico_ca
- clovis_ca
- columbia_md
- concord_ca
- corona_ca
- daly_ca
- downey_ca
- east los angeles_ca
- enterprise_nv
- fullerton_ca
- glendale_ca
- highlands ranch_co
- honolulu_hi
- huntington beach_ca
- indianapolis_in
- jurupa valley_ca
- lehigh acres_fl
- lowell_ma
- macon_ga
- menifee_ca
- metairie_la
- miami gardens_fl
- murrieta_ca
- norwalk_ca
- paradise_nv
- riverview_fl
- roseville_ca
- san buenaventura_ca
- san mateo_ca
- san tan valley_az
- sandy springs_ga
- santa clarita_ca
- santa rosa_ca
- south fulton_ga
- spokane valley_wa
- spring hill_fl
- spring valley_nv
- sugar land_tx
- sunrise manor_nv
- temecula_ca
- the woodlands_tx
- thousand oaks_ca
- victorville_ca
- visalia_ca
- west covina_ca
- wichita falls_tx

### County council composition (party/race/gender) — 67 cities missing entirely

-  alexandria_va
- amarillo_tx
- arlington_va
- athens clarke county_ga
- augusta richmond county_ga
- boston_ma
- brandon_fl
- bridgeport_ct
- brockton_ma
- centennial_co
- charlotte_nc
- chesapeake_va
- columbia_md
- columbus_ga
- east los angeles_ca
- elk grove_ca
- enterprise_nv
- hampton_va
- hartford_ct
- highlands ranch_co
- independence_mo
- indianapolis_in
- jackson_ms
- jurupa valley_ca
- kansas_mo
- las vegas_nv
- lee s summit_mo
- lehigh acres_fl
- lexington fayette urban county_ky
- louisville_ky
- macon_ga
- menifee_ca
- metairie_la
- nashville davidson county_tn
- new haven_ct
- new orleans_la
- new york_ny
- newport news_va
- norfolk_va
- north las vegas_nv
- norwalk_ca
- paradise_nv
- philadelphia_pa
- providence_ri
- richmond_va
- riverview_fl
- san buenaventura_ca
- san tan valley_az
- santa clarita_ca
- savannah_ga
- south bend_in
- south fulton_ga
- spokane valley_wa
- spring hill_fl
- spring valley_nv
- stamford_ct
- sunrise manor_nv
- temecula_ca
- the woodlands_tx
- thousand oaks_ca
- victorville_ca
- virginia beach_va
- visalia_ca
- washington_dc
- waterbury_ct
- wichita falls_tx
- worcester_ma

### Police chief identity (race/gender) — 60 cities missing entirely

-  arlington_va
- augusta richmond county_ga
- brandon_fl
- broken arrow_ok
- burbank_ca
- cambridge_ma
- centennial_co
- chico_ca
- clovis_ca
- columbia_md
- concord_ca
- corona_ca
- daly_ca
- downey_ca
- east los angeles_ca
- enterprise_nv
- fullerton_ca
- glendale_ca
- highlands ranch_co
- honolulu_hi
- huntington beach_ca
- indianapolis_in
- jacksonville_fl
- jurupa valley_ca
- lancaster_ca
- las vegas_nv
- lehigh acres_fl
- lowell_ma
- macon_ga
- menifee_ca
- metairie_la
- miami gardens_fl
- moreno valley_ca
- murrieta_ca
- norwalk_ca
- palmdale_ca
- paradise_nv
- pompano beach_fl
- rancho cucamonga_ca
- riverview_fl
- roseville_ca
- san buenaventura_ca
- san mateo_ca
- san tan valley_az
- sandy springs_ga
- santa clarita_ca
- santa rosa_ca
- south fulton_ga
- spokane valley_wa
- spring hill_fl
- spring valley_nv
- sugar land_tx
- sunrise manor_nv
- temecula_ca
- the woodlands_tx
- thousand oaks_ca
- victorville_ca
- visalia_ca
- west covina_ca
- wichita falls_tx


## Notes & caveats

- **Year span**: dense panel is 1990-2021. Years 2022-2024 are nearly empty because the upstream panel ends in 2021. The dataset includes those rows for forward-extension when newer data is appended.
- **UCR coverage gap**: the source panel `data_panel_post1990.rds` covers 398 cities; for COA cities not in that panel (typically smaller or non-reporting agencies), arrest/LEMAS data is NA. Raw yearly UCR arrest CSVs in `raw_data/arrests_csv_1974_2024_year/` could be used to extract additional cities at the cost of substantial processing (each file ~400 MB).
- **Vote share is presidential** at the county level (the only city-level political-control variable in the panel itself is `dem_in_power`/`demshare` from local elections, with thinner coverage). The presidential vote share is a useful proxy for local political lean.
- **Council composition is county-level** (from `countycouncils_comp.rds`). True city council composition is not in the supplied data sources.
- **Police killings (MPV)** start in 1999 and have a known undercount before 2013.
- **LEOKA employee data** is only available 2008-2019 in the supplied file.
- **CDP cities** (Highlands Ranch, Metairie, Paradise, etc.) have no incorporated-place fiscal/UCR data at all; they appear in the panel for COA-treatment context but most variables will be NA.

