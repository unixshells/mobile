# Unix Shells

Mobile SSH, Mosh, and SFTP client. iOS and Android.

## Features

- SSH (Ed25519/RSA key auth, agent forwarding, jump hosts)
- Mosh with native Dart crypto (no bundled C binary)
- SFTP file browser
- Relay integration (NAT traversal, no port forwarding)
- Auto-discovery of online latch devices
- Account sign-in via email approval (no tokens to copy)
- Per-device preferences (mosh, session name, key selection)

When connected via mosh to a latch server, SFTP runs over the
SSH connection that bootstrapped the mosh session.

## Building

```
flutter pub get
flutter run
```

## Dependencies

- [dartssh2](https://github.com/unixshells/dartssh2) -- SSH and SFTP
- [xterm.dart](https://github.com/unixshells/xterm) -- terminal widget
- [mosh-dart](https://github.com/unixshells/mosh-dart) -- mosh protocol

## License

Proprietary
