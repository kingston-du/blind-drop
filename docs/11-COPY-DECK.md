# 11 — Copy deck

Every user-facing string in the app. **Do not invent strings.** If you need one that is not
here, add it here in the same commit.

Keys go in `ios/BlindDrop/Resources/Localizable.strings`. English only in v1, but the file
exists so no string is ever inlined in a view.

---

## Voice

Dry, plain, active, a little arch. **The app never cheers.**

- Sentence case throughout. Not Title Case.
- **No exclamation marks.** Anywhere. This is enforceable by a lint rule; add one.
- Buttons name what happens and keep the name through the flow:
  **Drop a song → Seal it → Sealed.** Never "Submit". Never "Submitted". Never "Post".
- Empty states are invitations, not apologies. No "Oops", no "Nothing here yet!", no "Sorry".
- Errors say what happened and what to do about it. No blame, no "Something went wrong".
- Low readability is interesting, not losing. No "unfortunately", no consolation.
- No emoji in app copy. (Users put emoji in their display names; that is theirs.)

Words we don't use: *submit, post, share your vibe, awesome, oops, whoops, congrats, streak,
level up, don't miss out, hurry.*

---

## Onboarding

| Key | String |
|---|---|
| `onboarding.title` | Blind Drop |
| `onboarding.subtitle` | One song each, every day. Guess who submitted each song at the 8:00 PM reveal. |
| `onboarding.signin.apple` | Sign in with Apple |
| `onboarding.signin.review` | App Review Sign In |
| `onboarding.name.title` | What should we call you? |
| `onboarding.name.help` | This is the name people guess with. Use the one your friends use. |
| `onboarding.name.placeholder` | First name |
| `onboarding.name.error.empty` | Enter a name to continue. |
| `onboarding.name.error.long` | Keep it to 24 characters. |
| `onboarding.continue` | Continue |
| `onboarding.group.title` | Find your group |
| `onboarding.group.join` | Join a group |
| `onboarding.group.code.label` | Group code |
| `onboarding.group.code.placeholder` | 6-character code |
| `onboarding.group.help` | Six to twelve people. Nothing about a group is public. |
| `onboarding.group.code.error` | No group with that code. Check it and try again. |
| `onboarding.group.create` | Create a group instead |
| `onboarding.create.title` | Start a group |
| `onboarding.create.name.placeholder` | Group name |
| `onboarding.create.timezone` | Timezone |
| `onboarding.create.timezone.help` | Everyone plays on this group's clock. It can't be changed later. |
| `onboarding.create.timezone.search` | Search |
| `onboarding.create.timezone.close` | Close |
| `onboarding.create.hour` | Reveal at |
| `onboarding.create.hour.help` | Songs open ten hours before. Answers land two hours after. |
| `onboarding.create.action` | Create group |
| `onboarding.create.back` | Join a group instead |
| `onboarding.invite.title` | Your invite code |
| `onboarding.invite.help` | Send this to your group. They'll need it to get in. |
| `onboarding.invite.share` | Share invite |
| `onboarding.invite.done` | Go to today's round |

---

## The round's header

| Key | String |
|---|---|
| `menu.title` | Menu |

The `[≡]` in every phase's header (`08-SCREEN-SPECS.md` §2, §8). Not visible copy — it labels an
icon — but a control with no name is unreachable to VoiceOver, so it is a string and it lives here.

---

## The switcher

| Key | String |
|---|---|
| `switcher.title` | Your groups |
| `switcher.state.drop` | Drop a song |
| `switcher.state.sealed` | Sealed |
| `switcher.state.guess` | Guess |
| `switcher.state.answers` | Answers |
| `switcher.state.voided` | Voided |
| `a11y.switcher.opener.hint` | Double-tap to see all your groups |
| `a11y.switcher.opener.otherNeedsAction` | Another group wants your attention. |
| `a11y.switcher.row` | %@. %@. |
| `a11y.switcher.row.hint` | Double-tap to switch to this group |
| `a11y.switcher.attention` | Wants your attention. |
| `switcher.startGroup` | + Start a group |

`E19-02`. The group's name in the header (`08-SCREEN-SPECS.md` §2, §6, since E17-09) becomes the
control that opens this sheet. Its accessibility label is the group's own name — the visible
`Text` a `Button` wraps, unchanged — with `a11y.switcher.opener.hint` naming what tapping it
does; there is no separate "Switch group" label to keep in sync with the name beside it. When
some circle other than the one on screen wants attention, `a11y.switcher.opener.otherNeedsAction`
is a second sentence appended to that label — the VoiceOver channel for the small mark beside
the name, since `docs/12` §3 requires the mark not be colour-only and here it is not even
colour: a fact stated twice, once to the eye and once to the ear.

The five state words are a row's entire second column — `switcher.state.drop` reads the same as
`submit.action` and `switcher.state.sealed` the same as `sealed.badge` because they are naming
the same fact, but they are separate keys: a row is not a button and is not a badge, and a
future change to either of those two would have no business silently reading through into this
sheet's rows. `switcher.state.voided` is not one of the epic's four — `CircleState` (`docs/04`
§3) has a fifth case, an evening the caller's circle voided outright, and a row still has to
say something.

Nothing here names a member count, a submission count, or how many of a circle's people have
dropped — the same leak the round's own screens refuse (`CLAUDE.md` §2.1). A "needs your
attention" row sorts first with no visible heading; `a11y.switcher.attention` is the fact for a
VoiceOver user in place of the sighted reader's small mark, appended as its own sentence after
`a11y.switcher.row`'s name-and-state pair — two localized reads joined, the same shape
`Copy.A11y.result(...)` already uses for a results card's own optional second sentence — rather
than drawn as a second line. The row is still just a name and a state.

---

## Starting a group

| Key | String |
|---|---|
| `group.start.title` | Start a group |
| `group.start.name.placeholder` | Group name |
| `group.start.timezone` | Timezone |
| `group.start.timezone.help` | Set from this device. It can't be changed later. |
| `group.start.hour` | Reveal at |
| `group.start.hour.help` | Songs open ten hours before. Answers land two hours after. |
| `group.start.action` | Create group |
| `group.invite.title` | Fill the group |
| `group.invite.help` | Invite people you already play with, or send the link to someone new. |
| `group.invite.people` | People you've played with |
| `group.invite.empty` | Nobody from another group is here yet. The link works for anyone. |
| `group.invite.action` | Invite |
| `group.invite.link` | Invite link |
| `group.invite.share` | Share invite |
| `group.invite.done` | Go to the group |
| `group.join.title` | Join this group? |
| `group.join.by` | %@ invited you. |
| `group.join.action` | Join group |
| `group.join.decline` | Decline |

The timezone is stated, not asked, for a second group: it defaults from the device at creation
and stays fixed. `group.invite.people` is a shortcut derived from shared active memberships;
it is not a social graph, and the list carries no counts, profiles, or activity.

---

## Track links

| Key | String |
|---|---|
| `link.apple` | Apple Music |
| `link.spotify` | Spotify |

The service name alone, for a card's corner (Sealed, Results' answer card) where `record.open.*`'s
"Open in …" is too long to sit beside a stamp. Apple Music first, Spotify under it.

---

## How to play

| Key | String |
|---|---|
| `howto.title` | How to play |
| `howto.intro` | Everyone drops one song each, every day. Try and guess who dropped what, and create a group record (playlist) at the same time. |
| `howto.step1.title` | Drop a song |
| `howto.step1.body` | Search and seal your song for the day. Could be what you're listening to, or just a song you like. |
| `howto.step2.title` | The reveal |
| `howto.step2.body` | Every dropped song is revealed, anonymous and numbered. |
| `howto.step3.title` | Guess |
| `howto.step3.time` | 2 hours |
| `howto.step3.body` | Make your best guess, and put a name on every card. |
| `howto.step4.title` | Results |
| `howto.step4.body` | See your friends' real music taste, and how right or wrong you were. |
| `howto.scoring.title` | Scoring |
| `howto.ear.title` | Ear |
| `howto.ear.body` | How well you know your friends (musically at least). The percentage of answers you get correct. (Ranked) |
| `howto.read.title` | Readability |
| `howto.read.body` | How "readable", or guessable your music taste is. There's no bad or good, it's a spectrum. High and low scores are equally intriguing. (Unranked) |
| `howto.notes.title` | Good to know |
| `howto.note.void` | Fewer than three drops means every song is returned with no reveal/record addition. Get your friends to participate next time. |
| `howto.note.replace` | You can swap your song as many times as you want before the reveal. |
| `howto.note.watch` | If you don't drop a song, you don't get to play. Maybe you should participate next time. |
| `howto.note.record` | Again, every song dropped goes into "The Record" or a group playlist. It's exportable to Apple Music, or Spotify (bit iffy). |

The `[?]` beside `[≡]` in every phase's header, and alone in the top-right corner of sign-in
(`08-SCREEN-SPECS.md` §1.1, §2, §8) — the explainer is reachable before there is even a round.

The four steps' clock times (`howto.step1`, `.step2`, `.step4`) are never written down as
strings: they are `RevealHour.formatted(...)` against the group's own `reveal_hour`, so a group
that seals at 6:00 PM reads its own schedule rather than the 8:00 PM default. `howto.step3.time`
is the one literal — the two-hour guess window is a constant, not a group setting. No step names
the phase it happens in (`sealed` / `live` / `scored`) — the time alone says when, and a phase
word beside it repeated a fact the countdown already carries.

---

## Submit — open, nothing dropped

| Key | String |
|---|---|
| `submit.headline` | Today's song. |
| `submit.subhead` | Nobody sees it until 8:00 PM. |
| `submit.countdown.label` | until reveal |
| `submit.action` | Drop a song |
| `submit.badge` | Seals in %@ |
| `submit.blind` | Drop your song of the day and see who knows your taste. |
| `submit.nudge` | Two hours left to drop. |
| `submit.closed.headline` | Tonight's round is done. |
| `submit.closed.subhead` | The next one opens at %@. |
| `submit.closed.countdown.label` | until it opens |

`%@` is a formatted local time like "10:00 AM".

---

## Search and confirm

| Key | String |
|---|---|
| `search.placeholder` | Search for a song |
| `search.results` | Results |
| `search.paste` | Paste a Spotify or Apple Music link |
| `search.paste.placeholder` | Paste a link |
| `search.close` | Close |
| `search.empty` | No songs matched that. |
| `search.error` | Search is down. Paste a Spotify or Apple Music link instead. |
| `search.error.offline` | You're offline. Nothing can be dropped right now. |
| `resolve.error.notfound` | That song isn't in the Apple catalog. Search for it instead. |
| `resolve.error.badlink` | That's not a song link. |
| `confirm.title` | Your song |
| `confirm.note` | Seal your song for the day. After %@ nothing about it changes. |
| `confirm.action` | Seal it |
| `confirm.another` | Pick another |
| `confirm.error` | That didn't seal. Try again. |

---

## Sealed

| Key | String |
|---|---|
| `sealed.status` | Sealed until %@. |
| `sealed.badge` | Sealed |
| `sealed.peek` | Hold to peek |
| `sealed.opens.label` | Opens in |
| `sealed.company` | Come back for the reveal to see today's drops. |
| `sealed.countdown.label` | until reveal |
| `sealed.replace` | Replace song |
| `sealed.replaced` | Sealed again. |
| `push.permission.title` | Want to know when it opens? |
| `push.permission.body` | Know when songs go up, and when answers land. Nothing else. |
| `push.permission.allow` | Turn on notifications |
| `push.permission.skip` | Not now |

`sealed.status` takes the group's reveal time, e.g. "Sealed until 8:00."

`sealed.peek` replaces the title and artist in place, in the same spot, until the card is held
(`E22-01`). VoiceOver never sees it — the sealed card's own label always names the title and
artist, held or not, which is the non-gesture path to the same information.

---

## Voided

| Key | String |
|---|---|
| `voided.headline` | Not enough drops tonight. Nothing revealed. |
| `voided.returned` | Your song came back. |
| `voided.next` | Next round opens at %@. |

Never state how many people did drop.

---

## Reveal and guess

| Key | String |
|---|---|
| `reveal.title` | Tonight's drop |
| `reveal.subtitle` | %lld songs |
| `reveal.countdown.label` | until answers |
| `reveal.card.prompt` | Who dropped this? |
| `reveal.card.prompt.short` | Name them |
| `reveal.card.mine` | Yours |
| `reveal.progress` | %lld of %lld assigned |
| `reveal.locked.title` | Locked in. |
| `reveal.callsheet` | Your call sheet |
| `reveal.callsheet.naming` | Naming No. %lld |
| `reveal.callsheet.expand` | Expand call sheet |
| `reveal.callsheet.collapse` | Collapse call sheet |
| `reveal.action` | Lock in guesses |
| `reveal.action.locked` | Locked in |
| `reveal.edit` | Change a guess |
| `reveal.blocked.notsubmitter` | You didn't drop tonight, so you're sitting this one out. |
| `reveal.blocked.joinedlate` | You joined after the reveal. You're in from tomorrow. |
| `reveal.blocked.canview` | You can still look. |

---

## Results

| Key | String |
|---|---|
| `results.title` | Answers |
| `results.card.owner` | %@ |
| `results.card.correct` | %lld of %lld got it |
| `results.card.nobody` | Nobody got it |
| `results.card.everybody` | Everybody got it |
| `results.card.tally` | %lld/%lld |
| `results.card.by` | Dropped by |
| `results.card.yousaid` | You said |
| `results.card.hit` | Hit |
| `results.card.miss` | Miss |
| `results.card.room` | How the room did |
| `results.you.title` | You |
| `results.readability.label` | Readability |
| `results.readability.detail` | %lld of %lld read you |
| `results.readability.none` | You didn't drop tonight. |
| `results.ear.label` | Ear |
| `results.ear.detail` | %lld of %lld correct |
| `results.ear.none` | You sat this one out. |
| `results.spectrum.low` | Unreadable |
| `results.spectrum.high` | Easy to read |
| `results.standings.title` | All time |
| `results.standings.rounds` | %lld rounds |
| `results.standings.row` | Ear %lld · Read %lld |
| `results.standings.ear` | Best ear |
| `results.standings.ear.detail` | %lld correct |
| `results.standings.readability` | How readable |
| `results.share` | Share tonight |
| `results.share.caption` | Your results |

### Readability bands

| Key | String |
|---|---|
| `band.open_book` | Clear |
| `band.legible` | Legible |
| `band.mixed_signals` | Mixed |
| `band.hard_to_place` | Elusive |
| `band.unreadable` | Unreadable |

No band is framed as good or bad. There is no copy anywhere that congratulates a high
readability or commiserates a low one.

### Share card headlines

| Key | String |
|---|---|
| `share.headline.nobody` | Nobody got No. %lld |
| `share.headline.everybody` | Everybody got No. %lld |
| `share.headline.perfect` | %@ read the whole room |
| `share.headline.unreadable` | %@ was unreadable |
| `share.headline.fallback` | %lld songs, %lld guesses |
| `share.overflow` | + %lld more | the cards that did not fit in the four rows (`docs/10` §2) |
| `share.bestear.label` | Best ear |
| `share.wordmark` | Blind Drop |

`share.wordmark` is *"the name at the bottom is the whole marketing"* (`docs/10` §2). It is its
own row rather than a reuse of `onboarding.title` because the two are different jobs: one is a
screen's headline and the other is a signature on an artifact leaving the app, and a change to
either must be able to happen without the other.

---

## The Record

| Key | String |
|---|---|
| `record.title` | The Record |
| `record.filter.all` | Everyone |
| `record.filter.member` | %@ |
| `record.filter.label` | Filter The Record by member |
| `record.subtitle` | Every song anyone has dropped, newest first. |
| `record.empty` | Nothing in the record yet. It starts filling tonight. |
| `record.empty.filtered` | %@ hasn't dropped anything yet. |
| `record.open.spotify` | Open in Spotify |
| `record.open.apple` | Open in Apple Music |
| `record.results` | See that night's results |
| `record.actions` | Song actions |
| `record.export.spotify` | Export to Spotify |
| `record.export.apple` | Export to Apple Music |
| `record.export.working` | Building the playlist |
| `record.export.done` | Playlist made. |
| `record.export.open` | Open it |
| `record.export.partial` | %lld songs aren't on %@. The rest are in. |
| `record.export.nosub` | Apple Music export needs a subscription. Spotify export still works. |
| `record.export.denied` | Apple Music access was turned down. You can still export to Spotify. |
| `record.export.failed` | The playlist didn't get made. Try again. |
| `NSAppleMusicUsageDescription` | Blind Drop uses Apple Music access only when you export The Record. |
| `a11y.record.track` | %@ by %@. Dropped by %@. |

---

## Group and settings

| Key | String |
|---|---|
| `group.title` | Group |
| `group.members` | Members |
| `group.loading` | Loading the group. |
| `group.role.admin` | Admin |
| `group.role.member` | Member |
| `group.name.label` | Group name |
| `group.name.help` | Everyone in the circle sees this. |
| `group.name.save` | Save name |
| `group.name.saved` | Saved. |
| `group.revealhour.label` | Reveal hour |
| `group.revealhour.help` | A change applies from the next round that hasn't been created yet — never tonight's. |
| `group.revealhour.effective` | Starts %@. |
| `group.timezone.label` | Timezone |
| `group.timezone.help` | Set when the circle was created. It can't be changed. |
| `group.leave` | Leave circle |
| `group.leave.confirm.title` | Leave this circle? |
| `group.leave.confirm.body` | Your songs and guesses stay in its history. You can rejoin later with an invite. |
| `group.leave.confirm.action` | Leave |
| `error.lastadmin` | You're the only admin here. This circle needs another one before you can leave. |
| `group.standings.thin` | Not enough rounds yet to rank anyone. |
| `group.admin` | Admin |
| `group.profile.placeholder` | Profile coming soon. |
| `settings.title` | Settings |
| `settings.profile` | Profile |
| `settings.name` | Display name |
| `settings.name.placeholder` | Display name |
| `settings.name.help` | This is the name people guess with. |
| `settings.save` | Save name |
| `settings.saved` | Saved. |
| `settings.account` | Account |
| `settings.signout` | Sign out |
| `settings.delete` | Delete account |
| `settings.delete.confirm.title` | Delete your account? |
| `settings.delete.confirm.body` | Your sign-in will be deleted. Your songs and guesses stay in the record as Former member. |
| `settings.delete.confirm.action` | Delete account |
| `settings.cancel` | Cancel |
| `settings.delete.reauth` | Sign in with the same Apple Account to finish deleting your account. |
| `settings.about` | About |
| `settings.privacy` | Privacy Policy |
| `error.authprovider` | Apple sign-in isn't answering. Try again. |

---

## The countdown

Every countdown on every screen renders through these. The label beside it belongs to the
screen (`submit.countdown.label`, `sealed.countdown.label`, `reveal.countdown.label`); these
are the number itself.

| Key | String |
|---|---|
| `countdown.unknown` | --:--:-- |
| `countdown.coarse.hours` | %lld hours |
| `countdown.coarse.minutes` | %lld minutes |
| `countdown.coarse.soon` | under a minute |

`countdown.unknown` is what shows before the first response and after returning from the
background, until a refetch lands (`13-IOS-APP-ARCHITECTURE.md` §5 rule 3). It is not a zero
and it is not a spinner — the app does not know what time it is and says so.

The three coarse strings replace `HH:MM:SS` above `.accessibility2`
(`12-ACCESSIBILITY.md` §1). They round **down**: "3 hours" with three hours and fifty minutes
left, because a countdown that says 4 and then drops to 3 eleven minutes later reads as broken.

`countdown.coarse.hours` and `countdown.coarse.minutes` use `.stringsdict` plural rules. Their
singular forms are **"1 hour"** and **"1 minute"**; their plural forms remain `%lld hours` and
`%lld minutes`.

---

## Errors and system states

| Key | Code | String |
|---|---|---|
| `error.offline` | — | You're offline. |
| `error.offline.stale` | — | Showing what we had. This may be out of date. |
| `error.generic` | `INTERNAL` | That didn't work. Try again. |
| `error.unauthenticated` | `UNAUTHENTICATED` | Sign in again to keep playing. |
| `error.noprofile` | `NO_PROFILE` | Pick a name first. |
| `error.notfound` | `NOT_FOUND` | That doesn't exist. |
| `error.invalidinput` | `INVALID_INPUT` | Check that and try again. |
| `error.wrongphase` | `WRONG_PHASE` | That's not available right now. |
| `error.notsubmitter` | `NOT_A_SUBMITTER` | You didn't drop a song tonight. |
| `error.joinedlate` | `JOINED_LATE` | You joined after the reveal. You're in from tomorrow. |
| `error.roundvoided` | `ROUND_VOIDED` | Not enough drops tonight. Nothing revealed. |
| `error.trackalreadyused` | `TRACK_ALREADY_USED` | You already used this today. |
| `error.alreadyingroup` | `ALREADY_IN_GROUP` | You're already in that circle. |
| `error.alreadyinvited` | `ALREADY_INVITED` | They already have an invitation to this group. |
| `error.circlelimitreached` | `CIRCLE_LIMIT_REACHED` | You're already in three groups. Leave one to join another. |
| `error.notadmin` | `NOT_ADMIN` | Only the group's admin can change that. |
| `error.lastadmin` | `LAST_ADMIN_MUST_TRANSFER` | You're the only admin here. This circle needs another one before you can leave. |
| `error.ratelimited` | `RATE_LIMITED` | Slow down a second. |
| `error.upstream` | `UPSTREAM_UNAVAILABLE` | The music catalog isn't answering. Try again in a minute. |
| `error.nogroup` | `NO_GROUP` | You're not in a group yet. |

---

## Notifications

| Kind | Title | Body |
|---|---|---|
| `reveal` | Blind Drop | Tonight's drop is open. |
| `results` | Blind Drop | Answers are in. |
| `nudge` | Blind Drop | Two hours to drop. |
| `void` | Blind Drop | Not enough drops tonight. Nothing revealed. |

Four kinds, at most three delivered to any one person on any one day (`reveal` and `void` are
mutually exclusive). The nudge never reaches anyone who has already dropped.

---

## VoiceOver

Not visible copy, but user-facing. See `12-ACCESSIBILITY.md` for where each is applied.

| Key | String |
|---|---|
| `a11y.card` | No. %lld. %@ by %@. |
| `a11y.card.guessed` | No. %lld. %@ by %@. Guessed as %@. |
| `a11y.card.unguessed` | No. %lld. %@ by %@. No guess yet. |
| `a11y.card.mine` | No. %lld. %@ by %@. Your song. |
| `a11y.card.hint` | Double-tap to choose who dropped this |
| `a11y.card.result` | No. %lld. %@ by %@. Dropped by %@. %lld of %lld got it. |
| `a11y.card.result.mine` | Your guess was %@. %@. |
| `a11y.sealed` | Your song is sealed. %@ by %@. Reveal in %@. |
| `a11y.countdown` | %@ until reveal |
| `a11y.countdown.answers` | %@ until answers |
| `a11y.namechip` | %@. %@ | (name, then one of the two below) |
| `a11y.namechip.unassigned` | Unassigned |
| `a11y.namechip.assigned` | Assigned to No. %lld |
| `a11y.guess.assigned` | No. %lld assigned to %@. | posted as an `.announcement` |
| `a11y.guess.clear` | Clear guess | the `✕` on an inline chip, as a named action |
| `a11y.guess.correct` | Correct | fills `a11y.card.result.mine`'s second placeholder |
| `a11y.guess.incorrect` | Wrong | the same slot, and the mark is a strike — never a cross |
| `a11y.rotor.songs` | Songs | the custom rotor over the reveal's cards (`docs/12` §2) |
| `a11y.rotor.song` | No. %lld | one entry in that rotor — the number is what it is jumped to by |
| `a11y.preview.play` | Play preview |
| `a11y.preview.stop` | Stop preview |
| `a11y.track` | %@ by %@ | (title, artist) — a search result row |
| `a11y.track.hint` | Double-tap to choose this song |
| `a11y.group.row.hint` | Double-tap to open their profile |
| `a11y.readability` | Readability %lld percent. %@. | (value, band) |
| `a11y.invite.code` | Your invite code is %@. | the code spelled out, one character at a time |
| `a11y.seal.done` | Sealed. |
| `a11y.unseal.done` | Songs revealed. |

`a11y.guess.correct` / `.incorrect` are the two words that fill `a11y.card.result.mine`. They
exist only for VoiceOver: on screen the same fact is a check or a strike (`docs/07` §2), and a
sighted reader is never handed the word *"Wrong"* about a song they guessed.

Seven of these rows were written down at `E08-04` rather than invented at a call site
(`CLAUDE.md` §6). `12-ACCESSIBILITY.md` §2 already specified every one of them in prose — the
two card and track-row hints, the two name-chip states that fill `a11y.namechip`'s second
placeholder, the assignment announcement, and the track row's own label — but none of them had
a key, so a component would have had to hardcode the words to satisfy the accessibility spec.
