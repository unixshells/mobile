import 'dart:ui';

const relayHost = 'unixshells.com';
const relayJumpHost = 'relay.unixshells.com';
const relaySSHPort = 22;
const apiBaseURL = 'https://unixshells.com';
const defaultSSHPort = 22;
const terminalType = 'xterm-256color';

// Theme colors — matches web terminal design system v4.
const bgDark = Color(0xFF131921);
const bgCard = Color(0xFF1c222c);
const bgSurface = Color(0xFF262d38);
const accent = Color(0xFF6bc26b);
const accentHover = Color(0xFF84d484);
const textBright = Color(0xFFF0F6FC);
const textDim = Color(0xFF8b949e);
const textMuted = Color(0xFF484f58);
const borderColor = Color(0xFF21262d);

// Legacy aliases.
const bgButton = bgSurface;
