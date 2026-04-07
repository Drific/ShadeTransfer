# ShadeTransfer

P2P File Transfer Application built with Flutter.

## Features

- **End-to-end encryption** - AES-256 + RSA encryption protects your data
- **Peer-to-peer transfer** - Direct connection, no intermediate server required
- **QR code signaling** - Exchange connection info via QR code or text
- **Image QR scanning** - Scan QR codes from image files
- **Resumable transfers** - Pause and resume file transfers
- **Cross-platform** - Supports Windows, Android, Linux, iOS, macOS

## How It Works

1. **Sender**: Select file -> Generate QR code -> Scan receiver's answer QR -> Transfer begins
2. **Receiver**: Scan sender's QR code -> Generate response QR -> Wait for connection -> Receive file

## Build

### Windows
```bash
flutter build windows
```

### Windows MSIX
```bash
flutter pub run msix:create
```

### Android
```bash
flutter build apk
```

## Dependencies

- `flutter_webrtc` - WebRTC P2P connection
- `qr_flutter` - QR code generation
- `mobile_scanner` - QR code scanning (camera + image)
- `image_picker` - Image selection for QR scanning
- `file_picker` - File selection
- `encrypt` / `pointycastle` - Encryption
- `provider` - State management
- `msix` - Windows MSIX packaging
