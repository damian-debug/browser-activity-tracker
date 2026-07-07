# Chrome Web Store listing copy

Paste these directly into the Store Listing tab of the Developer Dashboard.

## Short description (132 char limit)

Automatic project time tracking for freelancers and agencies. 100% local storage, zero network calls, no account.

(113 characters)

## Category

Productivity

## Detailed description

Stop manually logging your hours. Browser Activity Tracker watches which tab
is active and automatically attributes your time to the right project, so
there are no timers to start and no forgetting to log a session.

HOW IT WORKS

The extension tracks the active tab in real time, pausing automatically when
you're idle or the browser loses focus, so only genuine working time counts.
Rules you define (by domain, URL, page title, or query parameter) assign that
time to a project automatically. For Figma and Bubble, it goes a step further
and recognizes individual files and apps, so time spent across multiple tabs
on the same Figma file or Bubble app rolls up as one continuous session
instead of fragmenting into noise.

KEY FEATURES

• Automatic tracking: starts and stops itself based on tab focus and idle
  state; nothing to remember to turn on
• Project rules: match by domain, URL contains/starts-with, path, query
  parameter, title, or regex, with priority and confidence scoring
• One-click manual override: reassign the current tab (or your whole
  browser) to a different project for a set time, until end of day, or until
  you switch back
• Review queue: anything unassigned or low-confidence surfaces in one place
  so nothing slips through unbilled
• Tags and billable flags: categorize time by type of work (development,
  design, QA, admin, etc.) and mark billable vs. non-billable
• Session editing: adjust start/end times, reassign a project after the
  fact, or split one session across two projects
• Dashboard: daily/weekly/monthly breakdowns by project, domain, and
  detected app/file, with a full session log and filters
• Full backup and restore: export everything (projects, tags, rules,
  sessions, settings) to a single file, and restore it on any device, merging
  or replacing as you choose
• CSV and JSON export: pull your tracked time into a spreadsheet, invoicing
  tool, or CRM

PRIVACY BY DESIGN

Every byte of data this extension collects, including sessions, projects,
rules, and settings, stays on your device in local browser storage. There is
no account, no sign-in, and no server: the extension makes zero network
requests, full stop. Moving to a new computer or backing up your history is
a manual export/import you control, not an automatic cloud sync.

WHO IT'S FOR

Freelancers, consultants, and small agencies who bill by project or need
accurate time records but don't want to run a timer manually or install a
heavyweight time-tracking suite with server-side accounts.

## Permission justifications (for the Privacy Practices tab)

- **tabs**: read the active tab's URL and title to detect which site/app is
  active and attribute time to it. Never used to inject scripts or read page
  content.
- **idle**: detect when the user is away from the keyboard so idle time
  isn't counted as active work.
- **storage**: persist sessions, projects, rules, tags, and settings locally
  in the browser. This is the extension's only data store.
- **alarms**: periodic heartbeat so an in-flight session survives the
  Manifest V3 service worker being suspended/restarted, and to end a timed
  manual override at the moment it expires.

## Single purpose description

Automatically tracks how much time is spent on each website/app and
attributes it to a user-defined project, entirely on-device.

## Contact

damian@goodspeed.studio
