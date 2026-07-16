# MCP Fantastical Server

[![npm version](https://img.shields.io/npm/v/mcp-fantastical.svg)](https://www.npmjs.com/package/mcp-fantastical)
[![CI](https://github.com/aplaceforallmystuff/mcp-fantastical/actions/workflows/ci.yml/badge.svg)](https://github.com/aplaceforallmystuff/mcp-fantastical/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![MCP](https://img.shields.io/badge/MCP-Compatible-blue)](https://modelcontextprotocol.io)

MCP server for [Fantastical](https://flexibits.com/fantastical) - the powerful calendar app for macOS.

## Why Use This?

- **Natural language event creation** - Use Fantastical's powerful natural language parsing ("Meeting with John tomorrow at 3pm")
- **View your schedule** - Check today's events or upcoming appointments without leaving your conversation
- **Quick calendar access** - Jump to any date in Fantastical instantly
- **Calendar-aware AI** - Let Claude understand your availability and schedule context
- **Zero configuration** - Works with your existing Fantastical and Calendar setup

## Features

| Category | Capabilities |
|----------|-------------|
| **Event Creation** | Create events using natural language, specify calendar, add notes |
| **Schedule Viewing** | View today's events, upcoming events for any number of days |
| **Navigation** | Open Fantastical to specific dates |
| **Search** | Search events by title, location, or notes |
| **Calendar Management** | List all available calendars |

## Prerequisites

- macOS
- Node.js 18+
- Your calendar accounts added in System Settings → Internet Accounts. Reads go through EventKit, which only sees what macOS itself syncs.
- [Fantastical](https://flexibits.com/fantastical) installed — required only for `fantastical_create_event` and the UI tools, which drive the `x-fantastical3://` URL scheme. Reading events does not need the app.

Xcode is **not** required. `npm install` installs the signed helper from `prebuilt/`. You only need a compiler and a signing certificate if you are changing the helper itself (see Development).

## Installation

### Using npm (Recommended)

```bash
npx mcp-fantastical
```

### From Source

```bash
git clone https://github.com/aplaceforallmystuff/mcp-fantastical.git
cd mcp-fantastical
npm install
npm run build
```

## Configuration

No API keys required - this server uses AppleScript to communicate with Fantastical and the Calendar app.

### For Claude Desktop

Add to your Claude Desktop config file:

**macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`

```json
{
  "mcpServers": {
    "fantastical": {
      "command": "npx",
      "args": ["-y", "mcp-fantastical"]
    }
  }
}
```

### For Claude Code

Add to `~/.claude.json`:

```json
{
  "mcpServers": {
    "fantastical": {
      "command": "npx",
      "args": ["-y", "mcp-fantastical"]
    }
  }
}
```

### Permissions

On first run, you may need to grant the following permissions:

**Accessibility (for event creation via URL scheme):**
1. System Preferences → Privacy & Security → Accessibility
2. Add Terminal (or your terminal app) to the allowed list

**Full Calendar Access (for reading events):**

The native helper ships as a signed `.app` bundle (`FantasticalHelper.app`) in `prebuilt/`, installed as-is by `npm install`. The first time the MCP server reads calendar data, macOS shows a one-time prompt attributed to **"FantasticalHelper"** asking to grant Full Calendar Access. Approve it.

The grant is per machine and cannot be copied between them. That is macOS policy, not a limitation of this server.

If you miss the prompt or need to re-grant later:
1. System Settings → Privacy & Security → Calendars
2. Enable **FantasticalHelper**

**If it denies with no prompt at all**, the bundle is missing its entitlement. Under hardened runtime, TCC requires `com.apple.security.personal-information.calendars` before it will even ask: without it the request is denied instantly, no dialog appears, and no decision is recorded — indistinguishable from you having clicked Deny. Check with:

```bash
codesign -d --entitlements - --xml dist/native/FantasticalHelper.app | plutil -p -
```

Note: prior versions shipped a raw helper binary, which macOS couldn't attribute a TCC permission to when launched under Claude Desktop — the prompt never appeared and access was silently denied ([#6](https://github.com/aplaceforallmystuff/mcp-fantastical/issues/6)). The bundled + signed helper fixes this.

## Usage Examples

### Creating Events
- "Schedule a meeting with the team tomorrow at 2pm"
- "Add dentist appointment Friday at 10am to my Personal calendar"
- "Create a recurring standup every Monday at 9am"
- "Block off next Tuesday afternoon for deep work"

### Viewing Schedule
- "What's on my calendar today?"
- "Show me my schedule for the next week"
- "What meetings do I have tomorrow?"
- "Am I free on Friday afternoon?"

### Navigation
- "Open my calendar to next Monday"
- "Show me December 25th in Fantastical"
- "Jump to next week in my calendar"

### Searching
- "Find all meetings with Sarah"
- "Search for dentist appointments"
- "Look up project review meetings"

## Available Tools

Tools split into two kinds. **Reads** go through EventKit via the native helper and
return data. **UI commands** drive Fantastical through its `x-fantastical3` URL scheme
and return nothing to the caller, because Fantastical exposes no read API.

| Tool | Kind | Description |
|------|------|-------------|
| `fantastical_get_today` | read | Today's events, with attendees, notes, and conference links |
| `fantastical_get_upcoming` | read | Events for the next N days, same fields |
| `fantastical_get_calendars` | read | List available calendars with their source |
| `fantastical_create_event` | write | Create an event using Fantastical's natural language parser |
| `fantastical_show_date` | UI | Open Fantastical to a specific date. Returns no data |
| `fantastical_open_search` | UI | Open Fantastical's search UI. **Returns no event data** |

## Development

```bash
# Watch mode for development
npm run watch

# Build TypeScript
npm run build

# Run locally
node dist/index.js
```

### Changing the native helper

`npm install` installs the signed bundle from `prebuilt/` and never compiles, so a
change to `native/FantasticalHelper.swift` has no effect until you rebuild it.

Building from source needs Xcode Command Line Tools and a codesigning identity:

```bash
security find-identity -v -p codesigning
export MCP_FANTASTICAL_SIGN_IDENTITY="Apple Development: Your Name (XXXXXXXXXX)"

npm run build:native      # build to dist/, for testing
npm run build:prebuilt    # build, then refresh prebuilt/ -- commit the result
```

The identity matters beyond mere signing. macOS records the calendar grant against
the bundle's designated requirement, which `build.sh` pins to the certificate's team
ID (`leaf[subject.OU]`) rather than its name, so the grant survives both rebuilds and
certificate reissues. Ad-hoc signing has no certificate at all: the identity becomes
the code hash, every rebuild reads as a different app, and the grant is lost each
time. That is why `build.sh` prefers copying `prebuilt/` over ad-hoc signing when no
identity is set.

Since the bundle is committed, `npm run build:prebuilt` is a required step when the
helper changes. Nothing runs it automatically — refreshing a committed binary on
every dev build would put a binary diff in unrelated commits.

## Troubleshooting

### "AppleScript error: Not authorized to send Apple events"
Grant accessibility permissions:
1. Open System Preferences → Privacy & Security → Accessibility
2. Click the lock to make changes
3. Add Terminal (or your terminal app) and enable it

### Calendar permission errors, or "Calendar access denied" under Claude Desktop
macOS TCC permissions don't inherit through the Claude Desktop → npx → node → helper chain. The native helper is wrapped in an ad-hoc-signed `FantasticalHelper.app` bundle so macOS has a stable code identity to attribute the calendar permission to.

**Solutions:**
1. Look for a one-time system prompt attributed to **FantasticalHelper** and approve it. If it appeared behind another window, restart your MCP client and retry.
2. Check System Settings → Privacy & Security → Calendars and enable **FantasticalHelper**.
3. If running from source, rebuild the bundle: `npm run build:native`.
4. If the bundle is missing a code signature for any reason, re-sign it: `codesign --force --sign - dist/native/FantasticalHelper.app`.

### "Error: This MCP server only works on macOS"
This server requires macOS because Fantastical is a macOS application. It uses AppleScript to communicate with Fantastical and the Calendar app.

### Events not showing up
- Ensure Fantastical is syncing with iCloud/Calendar
- Check that Calendar.app has access to the same calendars
- Verify the event was created in the correct calendar
- Grant Full Calendar Access (see above)

### Fantastical not opening
- Ensure Fantastical is installed
- Try opening Fantastical manually first
- Check that URL schemes are enabled in Fantastical preferences

## License

MIT - see [LICENSE](LICENSE) for details.

## Links

- [Fantastical](https://flexibits.com/fantastical) - Official Fantastical website
- [Model Context Protocol](https://modelcontextprotocol.io) - MCP specification
- [GitHub Repository](https://github.com/aplaceforallmystuff/mcp-fantastical)
