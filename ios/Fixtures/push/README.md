# Push-routing simulator fixture

`results-other-circle.apns` is a simulator-only injection fixture for `E23-03`. It deliberately
names **Late Night Radio**, the fixture server's non-active circle, while that circle serves an
`open` round. The expected result is therefore that the app switches circles but renders its
sealed/open flow rather than a results screen: the push navigates; the server owns the phase.

Start the fixture server, launch the Debug app on the **iPhone 17** simulator with
`-apiBaseURL http://127.0.0.1:8787 -fixtureSession`, then inject the payload:

```sh
xcrun simctl push booted com.blinddrop.app ios/Fixtures/push/results-other-circle.apns
```

Run it once while the app is foregrounded (tap the banner), once while it is backgrounded, and
once after terminating it. The simulator proves payload handling and routing only. It cannot
register with APNs or prove a delivered remote notification; those checks remain for a physical
device.
