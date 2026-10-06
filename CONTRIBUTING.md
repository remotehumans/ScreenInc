# Contributing

Use macOS 14 or newer and Xcode command line tools. There are no third-party
Swift package dependencies. Clone the repository, run `swift test --disable-sandbox`,
then `./script/build_and_run.sh`. The executable target retains the name ScreenInk;
the product name is ScreenInc.

Open an issue for substantial changes. Keep pull requests focused and explain
the problem, resulting behaviour, and verification. Add regression tests for
behaviour changes. Never include private recordings, pairing URLs or credentials.

Camera, tablet, multi-monitor and permission behaviour need real device testing.
State which checks you actually performed; the verification documents track
current limitations. Contributions are provided under the MIT licence.
