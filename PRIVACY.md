# Headset Gesture Privacy

Headset Gesture processes headset button input and gesture timing locally on the Mac. It does not send headset events, configured actions, or usage analytics to the developer or to a remote service.

The app stores gesture mappings and timing preferences in the current user's macOS preferences. It requests Input Monitoring and Accessibility access only to read the supported headset signal and deliver the actions configured by the user.

If the user configures a Shortcut or shell command, that action runs locally with the user's permissions. Headset Gesture does not inspect or upload the content handled by that action. A user-configured command may itself access files or network services; that behavior is controlled by the command, not by Headset Gesture.

Removing the app does not automatically remove its macOS preferences or privacy permissions. Those can be reset from System Settings or with macOS command-line tools.
