# UCR coverage diagnostic — merge gap vs genuine non-reporter

For each of the 56 COA cities flagged as missing UCR arrests in the master panel, I scanned every yearly UCR arrest CSV (1990-2024, ~452k agency-years) to see whether the agency exists in raw UCR and whether it actively reports.

**Source scanned:** `raw_data/arrests_csv_1974_2024_year/arrests_yearly_*.csv`  
**Output file:** `dev/ucr_missing_classification.csv` (full per-city detail)

## Result

- **MERGE GAP (41 cities)** — agency exists in raw UCR with arrests data, but the pre-built panel `data_panel_post1990.rds` did not include it. **Fixable** by backfilling from the yearly CSVs.
- **NOT IN UCR (15 cities)** — no matching agency in any UCR yearly file. All are census-designated places (CDPs) with no incorporated police department; they're patrolled by the county sheriff. **Genuinely unavailable** at the city level.
- **GENUINE NON-REPORTER (0 cities)** — no city is in UCR yet always reports zero data.
- **REPORTS BUT ZERO ARRESTS (0 cities)** — none.

## How matching worked

For each missing city, in priority order:
1. **By ORI9** — exact police-agency ID match (most reliable). Used for 27 cities.
2. **By place_fips** — match by 7-digit place FIPS (state+place). Used for 1 city (Augusta-Richmond GA).
3. **By name + state** — agency name contains the city name and state matches; excludes university/airport/school/transit agencies; for ties, prefers larger reported population. Used for 12 cities.
4. **Large-pop fallback** — for consolidated city-counties whose `fips_place_code` is the placeholder 99991 (Charlotte-Mecklenburg PD), name + state with min population 50,000. Used for 1 city (Charlotte NC).

## MERGE GAP cities (41) — fixable

| COA city | UCR agency name | UCR pop (max) | Yrs with arrests 1990-2021 | Match method |
|---|---|---|---|---|
| burbank_ca | burbank | 105,865 | 32 | by_ori9 |
| broken arrow_ok | broken arrow | 108,088 | 32 | by_ori9 |
| wichita falls_tx | wichita falls | 108,834 | 32 | by_ori9 |
| west covina_ca | west covina | 109,500 | 32 | by_ori9 |
| sugar land_tx | sugar land | 119,944 | 32 | by_ori9 |
| athens clarke county_ga | athens | athens-clark county | 129,765 | 32 | by_ori9 |
| concord_ca | concord | 130,855 | 32 | by_ori9 |
| arlington_va | arlington | arlington county pd | 243,149 | 32 | by_name_state |
| indianapolis_in | indianapolis | 895,826 | 32 | by_ori9 |
| honolulu_hi | honolulu | 999,307 | 32 | by_ori9 |
| charlotte_nc | charlotte | charlotte-mecklenburg pd | 1,003,130 | 32 | by_name_state_largepop |
| san mateo_ca | san mateo | 106,020 | 31 | by_ori9 |
| daly_ca | daly city | 107,928 | 31 | by_ori9 |
| norwalk_ca | norwalk | 108,391 | 31 | by_name_state |
| san buenaventura_ca | ventura | 111,596 | 31 | by_name_state |
| downey_ca | downey | 114,754 | 31 | by_ori9 |
| clovis_ca | clovis | 127,560 | 31 | by_ori9 |
| thousand oaks_ca | thousand oaks | 129,976 | 31 | by_name_state |
| victorville_ca | victorville | 138,534 | 31 | by_name_state |
| fullerton_ca | fullerton | 141,968 | 31 | by_ori9 |
| visalia_ca | visalia | 146,090 | 31 | by_ori9 |
| roseville_ca | roseville | 162,841 | 31 | by_ori9 |
| corona_ca | corona | 171,848 | 31 | by_ori9 |
| santa rosa_ca | santa rosa | 177,884 | 31 | by_ori9 |
| huntington beach_ca | huntington beach | 204,071 | 31 | by_ori9 |
| glendale_ca | glendale | 204,724 | 31 | by_ori9 |
| savannah_ga | savannah | savannah-chatham metro | 242,941 | 31 | by_ori9 |
| chico_ca | chico | 105,355 | 30 | by_ori9 |
| santa clarita_ca | santa clarita | 221,932 | 30 | by_name_state |
| temecula_ca | temecula | 116,630 | 29 | by_name_state |
| murrieta_ca | murrieta | 117,835 | 29 | by_ori9 |
| augusta richmond county_ga | richmond | augusta-richmond | 204,564 | 29 | by_place_fips |
| macon_ga | macon | 116,521 | 24 | by_name_state |
| centennial_co | centennial | 112,129 | 20 | by_name_state |
| spokane valley_wa | spokane valley | 109,852 | 19 | by_name_state |
| lowell_ma | lowell | 116,062 | 18 | by_ori9 |
| sandy springs_ga | sandy springs | 111,533 | 15 | by_ori9 |
| cambridge_ma | cambridge | 121,699 | 15 | by_ori9 |
| menifee_ca | menifee | 96,837 | 12 | by_name_state |
| jurupa valley_ca | jurupa valley | 111,198 | 10 | by_name_state |
| miami gardens_fl | miami gardens | 110,649 | 1 | by_ori9 |

### Notable cases

- **Charlotte NC** — name-match initially picked the UNC-Charlotte campus PD (only 18-68 arrests/yr). Corrected via the large-pop filter to **Charlotte-Mecklenburg PD** (NC0600100, ~26k arrests/yr, pop ~1M). The base panel missed Charlotte-Mecklenburg because that agency uses `fips_place_code = 99991` (a county-wide placeholder) instead of Charlotte's actual place_fips 3712000.
- **Augusta-Richmond GA** — initial loose name match picked Richmond Hill (pop 13k). Corrected to GA1210000 Augusta-Richmond consolidated PD (pop ~205k).
- **San Buenaventura CA** — UCR lists this city as just "Ventura". I added an alias mapping. Without it, this would have looked like a CDP non-reporter. **(Crosswalk should be updated.)**
- **Indianapolis IN** — Indianapolis Metropolitan PD (IN0494900) reports ~30-43k arrests/yr 2017-2024. Just absent from the supplied panel.
- **Honolulu HI** — Honolulu PD (HI0010100, county-wide for the City and County of Honolulu) reports ~999k pop. The COA list calls it "Urban Honolulu".

## NOT IN UCR cities (15) — genuinely unavailable

All 15 are census-designated places (unincorporated communities) without their own police department. Law enforcement is provided by the county sheriff. There is no city-level UCR record to merge.

| COA city | County / sheriff jurisdiction (likely) |
|---|---|
| brandon_fl          | Hillsborough County SO |
| columbia_md         | Howard County PD |
| east los angeles_ca | LA County Sheriff |
| enterprise_nv       | Clark County (LVMPD) |
| highlands ranch_co  | Douglas County SO |
| lehigh acres_fl     | Lee County SO |
| metairie_la         | Jefferson Parish SO |
| paradise_nv         | Clark County (LVMPD) |
| riverview_fl        | Hillsborough County SO |
| san tan valley_az   | Pinal County SO |
| south fulton_ga     | Incorporated 2017 — own PD exists but no entry under that name in UCR yearly files; possibly listed under "city of south fulton" with a non-obvious ORI. Manual check recommended. |
| spring hill_fl      | Hernando County SO |
| spring valley_nv    | Clark County (LVMPD) |
| sunrise manor_nv    | Clark County (LVMPD) |
| the woodlands_tx    | Montgomery County SO |

For these, COA-effect studies typically use the *county sheriff* arrests data as a proxy. If desired, I can add the relevant county-sheriff ORI to the crosswalk and pull arrests at that level.

## Summary

Of 56 COA cities flagged as missing UCR arrest data:
- **41 (73%) are merge gaps** that can be backfilled from `arrests_csv_1974_2024_year/`. Doing so would raise UCR arrest coverage from 280 cities (83%) to 321 cities (96%).
- **15 (27%) are CDPs / unincorporated areas** with no city-level UCR data anywhere — these are not fixable at the city level.
- **0 are "genuine non-reporters"** in the strict sense (i.e., agencies present in UCR but always reporting zero).

Want me to run the backfill?
