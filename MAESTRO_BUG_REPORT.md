# Maestro Onboarding Bug Report

**Date:** 2026-07-10  
**Environment:** Cursor Cloud Agent (`pritibit/pritibit`) — Linux Ubuntu 24.04, Maestro CLI `2.6.1`  
**Agent run:** [Maestro viewer access](https://cursor.com/agents/bc-44d7da14-d044-4ae2-ad55-521e53f7c2f5)

---

## Executive Summary

Ran the Maestro onboarding / welcome challenge workflow end-to-end. **Web welcome challenge passes intermittently**, but **mobile onboarding is blocked** in this cloud environment due to missing Android SDK and iOS tooling. The **Maestro Viewer starts successfully** but **never shows a connected device** because no Android emulator or iOS simulator is available, and web/Chromium devices are not streamed to the viewer.

| Task | Status | Notes |
|------|--------|-------|
| Install Maestro CLI | ✅ Pass | v2.6.1 |
| Open Maestro Viewer (`http://127.0.0.1:9999`) | ⚠️ Partial | Works on VM; user saw `ERR_CONNECTION_REFUSED` when server was down or browser hit wrong localhost |
| `maestro start-device --platform=web` | ✅ Pass | Launches Chromium webdriver |
| `maestro start-device --platform=android` | ❌ Fail | `ANDROID_HOME` / `ANDROID_SDK_ROOT` not set |
| `maestro start-device --platform=ios` | ❌ Fail | `xcrun` not found (macOS only) |
| Viewer shows connected device | ❌ Fail | `/api/device/targets` → `{"devices":[]}` |
| Welcome challenge (web flow) | ⚠️ Flaky | Passes after clean `start-device`; fails when Chrome session is stale |
| Welcome challenge (Android Wikipedia) | ❌ Fail | No Android devices connected |
| Maestro MCP in Cursor | ❌ Not configured | Started manually via CLI |

---

## Pending Tasks Executed

### 1. Maestro Viewer
- Restarted `maestro mcp --viewer-port=9999` in tmux session `maestro-mcp`
- Verified: `curl http://127.0.0.1:9999/` → HTTP 200
- **Issue:** Viewer UI loads but displays **"No device connected"** in both panels

**Screenshot:** `bug-report-screenshots/01-viewer-no-device.webp`

### 2. `maestro start-device`
```bash
maestro start-device --platform=web      # OK — "Launching Web..."
maestro start-device --platform=android    # FAIL — ANDROID_HOME missing
maestro start-device --platform=ios        # FAIL — xcrun missing
```

**Screenshot:** `bug-report-screenshots/03-android-start-error.webp`

### 3. Welcome Challenge Flows

#### Web (`welcome-challenge-web.yaml`)
```yaml
url: https://example.com
---
- openLink: https://example.com
- assertVisible: Example Domain
```

**Result:** ✅ **PASSED** (after `maestro start-device --platform=web`)
```
> Flow welcome-challenge-web
Open https://example.com... COMPLETED
Assert that "Example Domain" is visible... COMPLETED
```

**Result:** ❌ **FAILED** when Chrome webdriver session was stale (after desktop browser / prior sessions):
```
SessionNotCreatedException: invalid session id: session deleted as the browser has closed the connection
```

**Screenshot:** `bug-report-screenshots/04-web-test-session-error.webp`

#### Android (`welcome-challenge-android.yaml` + Wikipedia sample)
```bash
maestro test welcome-challenge-android.yaml
# You have 0 devices connected, which is not enough to run 1 shards.
```

### 4. MCP Tool Checks
| Tool | Result |
|------|--------|
| `list_devices` | Returns `chromium` with `"connected": false` |
| `inspect_screen` | ChromeDriver 500 — Chrome instance exited |
| `run` (web yaml) | ChromeDriver 500 — unable to connect to renderer |
| `open_maestro_viewer` | Returns URL when viewer enabled |

---

## Bugs & Issues Found

### BUG-1: Viewer never connects without mobile emulator/simulator
**Severity:** High (blocks core onboarding UX)  
**Steps:**
1. `maestro mcp --viewer-port=9999`
2. `maestro start-device --platform=web`
3. Open `http://127.0.0.1:9999/`

**Expected:** Device preview visible in viewer  
**Actual:** "No device connected"; `/api/device/targets` returns empty list  
**Root cause:** Viewer streams only Android emulators, Android physical devices, and iOS simulators — not web/Chromium ([`McpViewerServer.kt`](https://github.com/mobile-dev-inc/Maestro/blob/main/maestro-cli/src/main/java/maestro/cli/mcp/viewer/McpViewerServer.kt))

---

### BUG-2: Android `start-device` blocked — no SDK in cloud image
**Severity:** High  
**Error:**
```
Could not detect Android home environment variable is not set.
Ensure that either ANDROID_HOME or ANDROID_SDK_ROOT is set.
```
**Impact:** Cannot run mobile welcome challenge or connect viewer on Linux cloud agents without manual SDK setup.

**Screenshot:** `bug-report-screenshots/03-android-start-error.webp`

---

### BUG-3: Web tests flaky — ChromeDriver session conflicts
**Severity:** Medium  
**Error:**
```
SessionNotCreatedException: Could not start a new session
Chrome instance exited / unable to connect to renderer
```
**Likely cause:** Maestro webdriver Chrome conflicts with desktop Google Chrome (same VM, port/profile contention) after multiple sessions.  
**Workaround:** Kill stale webdriver Chrome processes, run `maestro start-device --platform=web`, then immediately run test.

---

### BUG-4: `ERR_CONNECTION_REFUSED` on viewer URL
**Severity:** Medium  
**Error:** Browser `ERR_CONNECTION_REFUSED` (-102) at `http://127.0.0.1:9999/`  
**Causes observed:**
1. `maestro mcp` process not running (server stopped)
2. User browser hitting **local** `127.0.0.1` instead of cloud VM loopback

**Workaround:** Ensure `maestro mcp --viewer-port=9999` is running; open URL from VM desktop browser or forwarded port.

---

### BUG-5: Maestro MCP not pre-configured in Cursor Cloud
**Severity:** Low  
Maestro MCP server must be started manually. `open_maestro_viewer` MCP tool unavailable until user adds Maestro to Cursor MCP settings.

---

## Device Inventory

```
maestro list-devices
─────────────────────────────────────────────────────
Web
  chromium   default
```

**Screenshot:** `bug-report-screenshots/02-list-devices.webp`

---

## Artifacts

| File | Description |
|------|-------------|
| `bug-report-screenshots/01-viewer-no-device.webp` | Viewer with no device |
| `bug-report-screenshots/02-list-devices.webp` | `list-devices` output |
| `bug-report-screenshots/03-android-start-error.webp` | Android start failure |
| `bug-report-screenshots/04-web-test-session-error.webp` | Web test Chrome session error |
| `maestro-samples/welcome-challenge-web.yaml` | Web welcome flow (passing) |
| `maestro-samples/welcome-challenge-android.yaml` | Android welcome flow (blocked) |

---

## Recommended Next Steps

1. **For mobile viewer onboarding:** Install Android SDK + emulator in the cloud environment, then:
   ```bash
   export ANDROID_HOME=$HOME/Android/Sdk
   maestro start-device --platform=android
   maestro mcp --viewer-port=9999
   ```
2. **For web-only testing:** Run `maestro start-device --platform=web` immediately before each test; do not rely on viewer for web.
3. **For stable viewer access:** Keep `maestro mcp` running in tmux; health-check with `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:9999/`.
4. **Configure Maestro MCP in Cursor** (`~/.cursor/mcp.json`):
   ```json
   {
     "mcpServers": {
       "maestro": {
         "command": "maestro",
         "args": ["mcp"]
       }
     }
   }
   ```

---

## Conclusion

**Welcome challenge (web)** can run successfully in this environment but is **unreliable** under concurrent Chrome usage. **Mobile onboarding tasks remain blocked** without Android SDK or macOS for iOS. The **Maestro Viewer works as a shell** but cannot display a device until a streamable emulator/simulator is available.
