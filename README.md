# Unix Shells

Mobile SSH, Mosh, and SFTP client. iOS and Android.

## Features

- SSH (Ed25519/RSA key auth, agent forwarding, jump hosts)
- Mosh with native Dart crypto (no bundled C binary)
- SFTP file browser
- Local terminal (Android, macOS, Linux)
- Cloud sync for connections and keys (E2E encrypted)
- Relay integration (NAT traversal, no port forwarding)

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
