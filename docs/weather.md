# Weather

Typing `weather` shows a weather card for where the owner is; `weather tokyo`, `weather in tokyo` and
`weather for tokyo` show a place. The card leads the launcher's results once the forecast and the place
are known: the current temperature and conditions, the place, today's high and low, an hourly strip
(Today) and a daily strip (This Week). Tab or a click switches the strip. Return opens Apple's Weather
app.

## Where forecasts come from

Forecasts come from Apple's WeatherKit through `VolantWeatherHost`, an XPC helper with only the
`network.client` and WeatherKit entitlements. The main app keeps no network access. The helper's two
calls take coordinates already rounded to 0.1 degrees, or a place name that `WeatherQuery` accepts
(1 to 100 characters, no control characters). Apple's geocoder turns either into a place name and time
zone; WeatherKit gives current conditions, hourly and ten-day forecasts. The helper replies with a
`WeatherReport` (the card's `ExtensionItemForecast`, temperatures in Celsius and the place's wall-clock
times) or a `HostMessage` code, never a raw service response. Conditions are worded by WeatherKit in the
owner's language, and the app shows temperatures in the owner's units.

## When it asks

- Nothing is asked while typing: the app waits for typing to pause (0.45 seconds) and asks only for the
  query still typed.
- Each place's forecast is kept in memory for ten minutes, and a failure for thirty seconds, so an
  outage or a refused location clears. Nothing is written to disk, logged, synced or ranked; weather
  rows are left out of usage stats because their identity includes the typed place.
- `weather` alone uses `ExtensionLocationProvider`: Location Services is asked the first time, never at
  startup, and the fix is rounded to 0.1 degrees and kept in memory for at most 15 minutes. Without
  Location, the card explains how to allow it or type a place.

WeatherKit's included quota (500,000 calls a month) is shared by every Volant user, which is why the
pause and the cache matter.

## Attribution

WeatherKit's terms require the Apple Weather mark and a link to Apple's data sources wherever its data
shows. The helper fetches the marks once per process from the URLs WeatherKit's attribution names, only
over https from apple.com, at most 128 KB each and only PNG. The card shows the mark for its appearance
and a Data Sources link.

## Signing

WeatherKit is a restricted entitlement, so `VolantWeatherHost` needs a provisioning profile, and its App
ID (`com.mysticcoders.volant.WeatherHost`) must have WeatherKit on in both Capabilities and App Services.
Debug builds use the automatic development profile. Release builds use a Developer ID profile named
**Volant mobile weather Developer ID**, which `Scripts/release.sh` and `Scripts/ExportOptions.plist` name;
the release script checks that the helper has exactly the sandbox, network client and WeatherKit
entitlements.

## Extension forecasts

A list extension row may carry a `forecast` with the same fields, which the launcher draws as the same
card without the Apple attribution; Return opens the Weather app unless the row has a link of its own. The
catalog's Weather extension does this for Open-Meteo forecasts.
VolantCore drops unknown symbols, implausible temperatures and unparsable times, and keeps at most 24
hours and 10 days.

## Evidence

- `WeatherTests` and `ExtensionItemForecastTests` (Core): query parsing, cache keys, report decoding and
  attribution checks, forecast limits, units and labels.
- `WeatherStoreTests` (app), with a fake helper, location and clock: the pause, one request per place,
  the ten-minute cache, refused location, worded helper codes and cancellation.
- The launcher Actions fixture renders the extension card and the built-in card in light and dark, and
  checks Tab and that nothing is asked while typing.
- None of these reach WeatherKit. A live forecast needs the signed helper with WeatherKit enabled for its
  App ID; the first run on 2026-11-13 failed WeatherKit's authentication until the App Services switch
  was on.
