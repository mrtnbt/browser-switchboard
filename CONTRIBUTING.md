# Contributing

Build the app and run the self-tests before submitting changes.

```sh
bash ./build.sh
"build/Browser Switchboard.app/Contents/MacOS/BrowserWeiche" --self-test
```

Source code lives in `Sources/`. English strings are written in the Swift source. Update `Sources/Resources/de.lproj/Localizable.strings` when you add or change a translatable string. Verify the settings and chooser in both languages when changing the interface.

When reporting a routing issue, include the app version, macOS version, source app, expected browser, and actual browser. Use a public test link such as `https://example.com/` instead of sharing private links or diagnostic logs containing personal details.
