# GitHub Startup Splash And Motivation Live Activity

## Scope

Add a native startup animation based on hAiity's GitHub contribution tiles and
turn the existing daily motivational notification into a server-free Live
Activity when the user returns to the app after its scheduled time.

The startup animation and motivation activity are independent. Startup must
never wait for GitHub authentication, cached graph data, CloudKit, or any
network request.

## Startup Experience

The app keeps its static `UILaunchScreen` for the system launch phase. As soon
as the app renders, a full-screen `StartupSplashView` is shown above the real
`ContentView`:

1. A compact cluster of deterministic GitHub-style tiles rests in the center.
2. The tiles spread outward into a contribution-grid shape.
3. The camera pushes through the center in a Netflix-style zoom while the
   tiles move beyond the screen edges.
4. The habit page is revealed only at the final transition frame.

The animation plays on every launch and has no skip control. The main view is
not faintly visible behind the initial animation. The existing app boot can
continue underneath the overlay; the splash does not wait for remote work.

The splash reuses the existing GitHub green palette and tile sizing rules. Its
levels are deterministic local placeholders so the visual is stable before a
GitHub account is connected. Reduce Motion keeps the same sequence and timing
but replaces the large movement with a restrained scale and fade.

## Motivation Live Activity

The existing motivation setting and local notification planner remain the
source of truth for whether motivation is enabled, its scheduled time, and the
day's generated message. The local notification remains necessary because a
local notification cannot start a new Live Activity while the app is
suspended.

When hAiity launches or returns to the foreground:

- Before today's configured motivation time, no motivation activity is
  created.
- At or after the configured time, hAiity creates one motivation activity for
  today's `DayKey` if today's activity has not already been shown or
  dismissed.
- The title and body are generated once from `Motivation.message(...)` and
  captured by the activity, so later name changes do not rewrite today's
  message.
- The activity receives the next local midnight as its stale date.
- On the next foreground after the day changes, the old activity is ended and
  the new day is eligible.
- Turning motivation off ends active motivation activities immediately.

The activity is dismissible through a Live Activity intent and ordinary system
dismissal. A per-day marker in the shared App Group prevents a dismissed
activity from being recreated during that day. A failed ActivityKit request
does not block the app or remove the existing local notification behavior.

## Components And Boundaries

- `StartupSplashView` owns only the launch animation and its phase timeline.
- The app root owns splash visibility and places the splash above
  `ContentView`; the habit UI remains the existing source of truth for app
  state.
- `MotivationActivityAttributes` is shared by the app and widget extension.
  It carries the day key and the captured localized message. Its content state
  carries only the data needed by the Live Activity rendering.
- `MotivationActivityManager` owns reconciliation, duplicate prevention,
  midnight cleanup, ActivityKit authorization checks, and activity requests.
- A dedicated `MotivationActivityControl` and
  `DismissMotivationActivityIntent` own ending and manual dismissal. The
  existing habit-session activity remains separate.
- The widget extension adds a motivation `ActivityConfiguration` to its
  existing bundle. The Lock Screen view shows the message and dismissal
  action; Dynamic Island compact, minimal, and expanded regions use the same
  captured content.

Motivation does not add a backend, push token, new notification planner, or
second settings store.

## Reconciliation Triggers

The motivation manager runs after local app boot, on every transition to the
active scene phase, and after changes to the motivation setting or time. The
reconciliation is idempotent:

- Existing activity for today's day is preserved.
- An old-day activity is ended.
- A disabled setting ends all motivation activities.
- A future scheduled time does not start an activity.
- A successful start records the day key only after ActivityKit accepts the
  request.

The existing `Reminders.reschedule` flow continues to schedule the daily local
motivation notification for future days. Opening hAiity after that notification
is the point at which the Live Activity can be started without a server.

## Verification

Automated tests will cover:

- no activity before the configured time;
- activity creation after the configured time;
- no duplicate activity for the same day;
- dismissal preventing same-day recreation;
- old-day cleanup and next-day eligibility;
- disabled motivation ending active activities;
- invalid settings and ActivityKit denial as non-fatal paths;
- deterministic splash phase timing and placeholder tile generation.

The app will be generated and built with the existing XcodeGen project, and
the complete test suite will run. The app will be launched on an iOS 27
simulator and inspected in screenshots or recorded frames for the centered
cluster, outward spread, center zoom, and final habit-page reveal. The
motivation Live Activity will be exercised with a deterministic debug time or
fixture and inspected on the Lock Screen/Dynamic Island surfaces where the
simulator supports them. No UI behavior will be reported as verified from
source inspection alone.
