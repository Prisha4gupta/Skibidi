# Info.plist privacy strings to add

Open the **LatestMap** target → **Info** tab in Xcode and add the following keys
(or paste the snippet into a raw Info.plist):

| Key | Suggested value |
| --- | --- |
| `NSHealthShareUsageDescription` | Skibidi reads your steps, sleep, and heart rate to compute your daily energy score. |
| `NSHealthUpdateUsageDescription` | Skibidi may write workout data so your community can see your activity. |
| `NSLocationWhenInUseUsageDescription` | Skibidi shows your location on the map so your community can find you. |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | Skibidi keeps your community updated on your whereabouts when you're moving. |

## Raw snippet
```xml
<key>NSHealthShareUsageDescription</key>
<string>Skibidi reads your steps, sleep, and heart rate to compute your daily energy score.</string>
<key>NSHealthUpdateUsageDescription</key>
<string>Skibidi may write workout data so your community can see your activity.</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>Skibidi shows your location on the map so your community can find you.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Skibidi keeps your community updated on your whereabouts when you're moving.</string>
```

You will also need to enable the **HealthKit** capability under
*Signing & Capabilities* on the target.
