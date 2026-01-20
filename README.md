# Metric

A macOS network routing manager that allows you to route traffic through specific network interfaces based on CIDR rules.

## Features

- **CIDR-Based Routing**: Define rules to route traffic to specific IP ranges through your preferred network interface
- **Transparent Proxy**: Uses macOS Network Extension framework with `NETransparentProxyProvider` for seamless traffic interception
- **Multiple Interface Support**: Automatically detects all available network interfaces (Ethernet, Wi-Fi, etc.)
- **Modern UI**: Clean, card-based interface with real-time status indicators
- **Rule Management**: Add, edit, delete, and reorder routing rules with drag-and-drop

## Screenshots

*Coming soon*

## Requirements

- macOS 11.0 (Big Sur) or later
- Apple Developer account with Network Extension entitlements
- Xcode 14.0 or later

## Installation

### From Source

1. Clone the repository:
   ```bash
   git clone https://github.com/missuo/Metric.git
   cd Metric
   ```

2. Open `Metric.xcodeproj` in Xcode

3. Configure signing:
   - Select your development team
   - Ensure Network Extension entitlements are properly configured in Apple Developer Portal

4. Build and run the project

### First Launch

1. Click **Install Extension** from the Metric menu
2. Allow the system extension in **System Settings > Privacy & Security**
3. Approve the VPN configuration when prompted

## Usage

### Adding a Routing Rule

1. Click the **+** button in the Routing Rules section
2. Enter a CIDR pattern (e.g., `192.168.1.0/24` or `10.0.0.1`)
3. Select the target network interface
4. Optionally add a comment
5. Click **Add**

### Managing Rules

- **Enable/Disable**: Toggle the checkbox next to each rule
- **Edit**: Double-click a rule to modify it
- **Delete**: Select a rule and click the **−** button
- **Reorder**: Drag and drop rules to change priority

### Starting the Proxy

Toggle the **Proxy** switch to start routing traffic according to your rules.

## Architecture

```
Metric/
├── Metric/                    # Main application
│   ├── AppDelegate            # App lifecycle management
│   ├── MainWindowController   # Main UI controller
│   ├── AddRuleViewController  # Rule editor
│   ├── RuleManager            # Rule persistence
│   ├── NetworkInterfaceManager # Interface detection
│   └── IPAddressHelper        # CIDR parsing utilities
├── MetricExtension/           # System Extension
│   ├── TransparentProxyProvider # NETransparentProxyProvider implementation
│   ├── FlowHandler            # TCP/UDP flow handling
│   └── RuleEngine             # Rule matching engine
└── Shared/                    # Shared code
    ├── RuleModel              # Rule data model
    └── SharedConstants        # App Group identifiers
```

## How It Works

1. **Traffic Interception**: The system extension intercepts outbound TCP connections using `NETransparentProxyProvider`

2. **Rule Matching**: Each connection is evaluated against your CIDR rules in priority order

3. **Interface Routing**: Matching traffic is routed through the specified network interface using `NWConnection` with interface constraints

4. **Passthrough**: Non-matching traffic passes through normally

## Limitations

- **TCP Only**: Currently only handles TCP traffic (UDP support planned)
- **Hostname Rules**: DNS resolution happens before traffic reaches the proxy, so hostname-based rules are not supported. Use CIDR rules instead.
- **System Apps**: Some system processes may bypass the transparent proxy

## Troubleshooting

### Extension Not Installing

1. Check **System Settings > Privacy & Security** for pending approvals
2. Ensure Network Extension entitlements are configured in Apple Developer Portal
3. Try rebooting if the extension shows "waiting to uninstall"

### Traffic Not Being Routed

1. Verify the proxy is running (green status indicator)
2. Check that rules are enabled (checkbox is checked)
3. Use Console.app to view extension logs (filter by `nz.owo.Metric`)

### Extension Status Shows "Not Installed"

1. Use **Metric > Install Extension** from the menu bar
2. Approve all system prompts

## Development

### Building

```bash
xcodebuild -project Metric.xcodeproj -scheme Metric -configuration Debug build
```

### Debugging the Extension

1. Enable System Extension developer mode:
   ```bash
   systemextensionsctl developer on
   ```

2. View logs in Console.app with filter: `nz.owo.Metric`

## License

*License information here*

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Acknowledgments

- Built with Apple's Network Extension framework
- Uses `NWConnection` for interface-specific routing
