# iOS build configurations

The app no longer hardcodes the API host or bundle identifier inside
`project.pbxproj`. Every environment value lives in an `.xcconfig` file under
`ios/Config/`, and the app reads them at runtime through `Info.plist`
(`API_BASE_URL`, `APP_ENVIRONMENT`) in `AppEnvironment.current`.

## Files

| File | API_BASE_URL | APP_ENVIRONMENT | Bundle id |
| --- | --- | --- | --- |
| `Config/Shared.xcconfig` | — (common settings) | — | base `com.dimalitin.lumabeautyid` |
| `Config/Dev.xcconfig` | `http://localhost:8010` | `development` | `…lumabeautyid.dev` |
| `Config/Staging.xcconfig` | `https://api-staging.lumatestdomen.online` | `staging` | `…lumabeautyid.staging` |
| `Config/Production.xcconfig` | `https://api.lumabeautyid.app` (placeholder) | `production` | `com.dimalitin.lumabeautyid` |

`Shared.xcconfig` holds the settings every environment shares (team, Swift
version, Info.plist path, marketing version). The three environment files
`#include "Shared.xcconfig"` and override only what differs.

> **xcconfig gotcha:** `//` starts a comment in xcconfig, so a URL is written
> `https:/$()/host` — the empty `$()` interpolation splits the `//` so it
> survives. The resolved value is still `https://host`.

## How configurations map today

The Xcode project ships two build configurations, wired via
`baseConfigurationReference`:

- **Debug → `Dev.xcconfig`** — `xcodebuild build/test` and local runs hit
  `localhost:8010` with the `.dev` bundle id.
- **Release → `Production.xcconfig`** — archives use the production host and the
  real `com.dimalitin.lumabeautyid` bundle id.

Verify what a configuration resolves to:

```sh
cd ios
xcodebuild -scheme BeautyConcierge -configuration Release -showBuildSettings \
  -destination 'generic/platform=iOS' | grep -E 'API_BASE_URL|APP_ENVIRONMENT|PRODUCT_BUNDLE_IDENTIFIER'
```

## Adding a dedicated Staging scheme

`Staging.xcconfig` is ready but not yet bound to its own build configuration so
the working two-configuration project stays intact. To expose a `-Staging`
scheme:

1. In Xcode, duplicate the **Release** configuration and name it `Staging`
   (Project → Info → Configurations).
2. Set its `baseConfigurationReference` to `Config/Staging.xcconfig`.
3. Duplicate the shared scheme to `BeautyConcierge-Staging` and point its
   Run/Archive actions at the `Staging` configuration.

The same recipe (duplicate Debug → `Dev`, Release → `Production`) produces
explicit `-Dev` / `-Production` schemes if per-scheme separation is preferred
over the current Debug=Dev / Release=Production mapping.

## Before App Store submission

Replace the `Production.xcconfig` `API_BASE_URL` placeholder
(`https://api.lumabeautyid.app`) with the real production host. The release-mode
guard in `AppEnvironment.releaseConfigurationError` rejects `localhost`,
`api.example.com`, and the `.invalid` fallback, so a misconfigured production
build fails closed with a user-facing "service unavailable" message instead of
silently calling the wrong host.
