class_name Balance
extends RefCounted
## Gameplay tuning in one place. Change difficulty here, not inside the systems.
## Mood values (atmosphere, club energy) run from 0 to 100.

# --- House party -------------------------------------------------------------
const PARTY_START_ATMOSPHERE := 54.0
## Seconds before the first guest arrives.
const PARTY_FIRST_ARRIVAL := .6
## Seconds between guests while the party is hot / lukewarm.
const PARTY_ARRIVAL_FAST := 2.4
const PARTY_ARRIVAL_SLOW := 3.7
## Atmosphere at which guests come faster, keep coming, or start leaving.
const PARTY_HOT_ATMOSPHERE := 67.0
const PARTY_INVITE_ATMOSPHERE := 50.0
const PARTY_LEAVE_ATMOSPHERE := 36.0
## Extra guests allowed above the goal before invitations stop.
const PARTY_OVERFLOW_GUESTS := 6
## How fast atmosphere follows its target (points per second).
const PARTY_ATMOSPHERE_RATE := 5.0
## Atmosphere target: base, requested-track bonus, wrong-track penalty, crowd-taste weight.
const PARTY_BASE_MOOD := 58.0
const PARTY_REQUEST_BONUS := 14.0
const PARTY_OFF_REQUEST_PENALTY := 3.0
const PARTY_TASTE_WEIGHT := 15.0
## After this many seconds on one track the crowd gets bored, by this many points per second.
const PARTY_TRACK_FATIGUE_AFTER := 95.0
const PARTY_TRACK_FATIGUE_RATE := .43
## Manual mixing: bass drives the mood; silence kills it.
const PARTY_BASS_WEIGHT := 16.0
const PARTY_SILENCE_PENALTY := 32.0
## Seconds between song requests (first one / later ones).
const PARTY_FIRST_REQUEST := 40.0
const PARTY_REQUEST_INTERVAL := 42.0
## Beat-mix key (M): cooldown, bonus per good hit, bonus cap, decay per second,
## and how close to the beat (fraction of a beat) counts as a hit.
const BEAT_MIX_COOLDOWN := 1.6
const BEAT_MIX_BONUS := 7.0
const BEAT_MIX_BONUS_MAX := 20.0
const BEAT_MIX_BONUS_DECAY := .75
const BEAT_MIX_WINDOW := .20

# --- Club shift ----------------------------------------------------------------
const CLUB_START_ENERGY := 54.0
const CLUB_START_GUESTS := 4
## How fast club energy falls / rises toward its target (points per second).
const CLUB_ENERGY_FALL_RATE := 2.7
const CLUB_ENERGY_RISE_RATE := 1.45
const CLUB_SMOOTH_TRANSITION_BONUS := 9.0
const CLUB_HARD_CUT_PENALTY := 8.0
const CLUB_VOLUME_JUMP_PENALTY := 7.0
## Seconds between door checks; energy that lets one more guest in / sends one out.
const CLUB_CROWD_TICK := 4.8
const CLUB_ADMIT_ENERGY := 58.0
const CLUB_DISMISS_ENERGY := 37.0
const CLUB_MIN_GUESTS := 2
## Seconds to solve an incident yourself / after handing it to staff (H).
const CLUB_EVENT_TIME := 28.0
const CLUB_STAFF_EVENT_TIME := 7.0
const CLUB_EVENT_SOLVED_BONUS := 9.0
const CLUB_EVENT_STAFF_BONUS := 4.0
const CLUB_EVENT_FAILED_PENALTY := 10.0

# --- Subway ----------------------------------------------------------------------
## Dollars the player gives a rider on the platform (E).
const SUBWAY_DONATION := 2

# --- New game ----------------------------------------------------------------------
const START_CASH := 18
const START_CIGARETTES := 3

# --- Night Shop ----------------------------------------------------------------
## Seconds an energy drink lasts.
const ENERGY_DRINK_DURATION := 45.0
