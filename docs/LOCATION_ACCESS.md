# Using your location

1. Open `http://localhost:3000/` directly in Chrome or Edge.
2. In Map, press **Use my location** (the target icon). Profile and the assistant
   use the same permission flow.
3. Choose **Allow** in the browser prompt. The app reads one position, updates
   nearby distances and shows your position on the map. No account is required.

If access was blocked, open the site controls beside the address bar, set
**Location** to **Allow**, then press **Try again** in the app. An embedded editor
preview may also need permission from its parent frame; the app offers **Open in
browser** when it detects an embedded context. It cannot override a browser's or
parent frame's denial.

On Windows, check **Settings → Privacy & security → Location**. Turn on Location
Services and allow desktop apps/browser access. A browser grant alone cannot
override disabled device location services.

On Android, turn on device Location and allow PasyalPH to use location while the
app is in use. Approximate location works for discovery. The Android manifest
includes both coarse and fine location permissions; no background permission is
requested. Native permission/settings paths are covered by platform-mocked tests;
an Android device build remains unverified because the SDK is not installed here.

The app uses a single, bounded browser position read, cancels its temporary watch
after success/failure/timeout, and shares simultaneous requests. A slow GPS fix
does not become a permanent permission denial. Missing Permissions API support
does not prevent requesting location. Failure never substitutes sample coordinates
for your actual position. You can still enter a city or starting address manually.

For a non-local deployment, use HTTPS. Plain HTTP on a LAN address does not get
the localhost secure-context exemption. The local server explicitly allows
same-origin geolocation while still requiring browser permission.

Reference: [Browser geolocation requirements](https://developer.mozilla.org/en-US/docs/Web/API/Geolocation/getCurrentPosition),
[geolocation Permissions Policy](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/geolocation).

Local verification uses `test/location_access_test.dart` and
`tools/location-browser-test.mjs`. The browser test runs in an isolated Chrome
profile with simulated Manila coordinates, testing allowed access, blocked access
and retry. It never changes permissions in your normal browser profile.
