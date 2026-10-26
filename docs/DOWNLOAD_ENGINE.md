# Download engine configuration and recovery

`lib/site_profiles.dart` defines domain-boundary matching and built-in site hints/defaults. yt-dlp remains responsible for extraction. The Aparat plugin remains an intentional exception for its public player API. Profiles leave User-Agent and extractor defaults to upstream unless a setting is needed; hard-coded browser identities are not applied to all sites.

`DownloadOptions` validates headers and settings, builds argv without a shell, and snapshots each inspection. A queued `Video` retains its own cookies, selected connection, original fallback connection plan, options and successful impersonation choice. The `upstream` extractor mode omits packaged plugins; `generic` explicitly forces the generic extractor. Proxy and cookie-file controls are shared UI inputs, copied or domain-scoped per inspected entry. Profiles never create proxies or automatically read browser cookies.

## Recovery policy

- yt-dlp performs its bounded internal retries first.
- Vidora permits at most four download attempts, reports `retrying`, and preserves partial files between attempts.
- Network/proxy failures can try system, direct, then a user-configured fallback proxy when the original mode was automatic. Explicit connection modes remain explicit.
- Supported sites can try browser impersonation for anti-bot/403 failures when enabled and when the actual bundled engine advertises a Chrome target. Cookie-bearing sessions are kept on their original connection/identity; see the implementation policy for session-bound failures.
- Expired media or unavailable formats trigger one metadata refresh. A changed format is accepted only when fallback is enabled, the container is compatible, and its height does not exceed the selected height. Custom selectors are not silently replaced.
- Login, cookie requirements, DRM, region restrictions and rate limits stop with actionable messages. A bare 403 remains an uncertain access refusal.

## Queue and files

Queue version 1 contains source URL, title, destination, stable ID, selected format, quality metadata, state, progress, non-session options and whether cookies must be re-selected. Cookies, their source path, User-Agent, Referer and custom headers are not serialized. Interrupted entries restore as paused; no download starts automatically. Re-inspection before resuming can require fresh authentication. The queue is atomically replaced and its previous valid snapshot is retained as `queue.json.bak`.

Partial media lives in `.local-video-<job-id>` inside the chosen destination. A private marker binds it to URL, selected streams, container and custom selector. A change to that identity discards incompatible parts. Pause and failure preserve parts; explicit cancellation removes them. Successful downloads move into the destination and clean their job folder. Server support for byte-range/fragment resumption and stable content is still required. Avoid editing partial folders manually while jobs run.

Diagnostics capture yt-dlp stderr (including verbose diagnostics and thumbnail operations) and download stdout/progress. Extraction JSON is parsed as metadata rather than logged. URL-bearing lines and sensitive values are redacted before persistence, with a 1 MB character budget per entry and retention of 100 entries. Exported logs use the same redacted content. Logs do not leave the device automatically.

## Updates and platform packaging

The installed engine version is queried locally. A 90-day age threshold warns that it may be stale; the optional update button checks only `api.github.com/repos/yt-dlp/yt-dlp/releases/latest`, without video/session data. Updates remain full reviewed application packages so signed bundles and the engine/plugin/Deno set stay consistent.

The GitHub `feat/persist-language` branch was incorporated locally. Its original changes did not include tests, a refreshed dependency lockfile or generated macOS plugin registration. The working implementation includes those, tolerates unavailable/corrupt preference reads and serializes preference writes.

The standalone macOS compiler currently expects Swift plugins, so the Foundation path provider is pinned to its Swift implementation. The Android path-provider backend is pinned to avoid adding a desktop JNI dependency for a platform this app does not ship.
