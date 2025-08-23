# tmux-claude-ext

A tmux extension that monitors Claude Code sessions across panes and windows, providing visual indicators when Claude needs user input or when activity has stalled. Never miss a prompt or stuck process again while multitasking!

## Features

- 🔍 **Automatic Detection** - Monitors all Claude Code sessions in tmux (including npx claude)
- 👁️ **Visual Indicators** - Status symbols in window tabs show which panes need attention
- ⏱️ **Timeout Detection** - Alerts when Claude sessions become inactive
- 🔔 **Multiple Notifications** - Bell, visual flash, or system notifications
- 🎨 **Customizable** - Configure symbols, colors, timeouts, and behaviors
- ⚡ **Lightweight** - Minimal resource usage with efficient shell scripts

## Visual Indicators

Window tabs show real-time status:
```
1:vim  2:claude[❓2,⏱3]  3:logs  4:claude[❓1]  5:shell
```

| Symbol | Meaning |
|--------|---------|
| ❓ | Input/choice needed |
| ⏱ | Activity timeout |
| 🤔 | Thinking/processing |
| ✅ | Task completed |
| ❌ | Error occurred |
| 🔄 | Active/running |

## Quick Start

### Installation

#### Using Make (Recommended)
```bash
git clone https://github.com/yourusername/tmux-claude-ext.git
cd tmux-claude-ext
make install
```

#### Manual Installation
```bash
git clone https://github.com/yourusername/tmux-claude-ext.git
cd tmux-claude-ext
./scripts/install.sh
```

### Basic Usage

1. **Start tmux** and run Claude Code in any pane
2. **Monitoring starts automatically** when Claude is detected
3. **Watch your window tabs** for status indicators
4. **Use key bindings** to manage alerts:
   - `Prefix + Ctrl-C` - Show status
   - `Prefix + Alt-C` - Clear alerts
   - `Prefix + Ctrl-N` - Go to next alert
   - `Prefix + Ctrl-M` - Toggle monitoring

## Commands

### Control Utility
```bash
# Show current status
tmux-claude-ctl status

# Clear alerts
tmux-claude-ctl clear       # Current pane
tmux-claude-ctl clear all   # All panes

# Navigate to alerts
tmux-claude-ctl goto

# Configure settings
tmux-claude-ctl config timeout 600  # 10 minute timeout
tmux-claude-ctl config notify bell  # Set notification type
```

### Monitor Control
```bash
# Manual control (usually automatic)
tmux-claude-monitor start
tmux-claude-monitor stop
tmux-claude-monitor status
```

## Configuration

Edit `~/.tmux.conf` or use `tmux-claude-ctl config`:

```bash
# Enable/disable monitoring
set -g @claude-monitor on

# Timeout before showing ⏱ (seconds)
set -g @claude-timeout 300

# Notification method (bell/flash/system/none)
set -g @claude-notify bell

# Display style (symbols/colors/both)
set -g @claude-style symbols

# Custom symbols
set -g @claude-symbol-choice "❓"
set -g @claude-symbol-timeout "⏱"
set -g @claude-symbol-error "❌"
set -g @claude-symbol-complete "✅"
```

## Advanced Features

### Pattern Customization

Edit `~/.tmux/plugins/tmux-claude-ext/conf/patterns.conf` to customize detection patterns:

```bash
PROMPT_PATTERNS=(
    "Choose one of:"
    "Enter your choice"
    "Would you like to"
    # Add your custom patterns
)
```

### Different Notification Styles

```bash
# System notifications (requires notify-send)
tmux-claude-ctl config notify system

# Visual flash
tmux-claude-ctl config notify flash

# Traditional bell
tmux-claude-ctl config notify bell

# Silent mode
tmux-claude-ctl config notify none
```

### Color Themes

```bash
# Symbols only (default)
tmux-claude-ctl config style symbols

# Colors only
tmux-claude-ctl config style colors

# Both symbols and colors
tmux-claude-ctl config style both
```

## Troubleshooting

### Monitor not starting
```bash
# Check if monitoring is enabled
tmux show-option -g @claude-monitor

# Start manually
tmux-claude-monitor start

# Check logs
cat /tmp/tmux-claude/monitor.log
```

### No indicators showing
```bash
# Verify Claude is detected
tmux-claude-ctl status

# Check pattern matching
tmux-claude-ctl analyze  # Analyze current pane
```

### Performance issues
```bash
# Increase monitoring interval
vim ~/.tmux/plugins/tmux-claude-ext/bin/tmux-claude-monitor
# Change MONITOR_INTERVAL=2 to higher value

# Reduce timeout checks
tmux-claude-ctl config timeout 600
```

## Development

### Project Structure
```
tmux-claude-ext/
├── bin/                    # Executable scripts
│   ├── tmux-claude-monitor # Main monitoring daemon
│   ├── tmux-claude-hook    # tmux event handlers
│   └── tmux-claude-ctl     # User control utility
├── lib/                    # Libraries
│   ├── state_manager.sh    # State management
│   ├── claude_patterns.sh  # Pattern detection
│   └── status_formatter.sh # Status formatting
├── conf/                   # Configuration
│   ├── tmux-claude.conf    # tmux configuration
│   └── patterns.conf       # Detection patterns
└── scripts/                # Installation
    ├── install.sh
    └── uninstall.sh
```

### Testing
```bash
# Run test suite
make test

# Lint shell scripts
make lint

# Development mode (symlinks)
make dev
```

### Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Requirements

- tmux 2.0 or higher
- bash 4.0 or higher
- Optional: `notify-send` for system notifications

## Uninstallation

```bash
# Using Make
make uninstall

# Or manually
~/.tmux/plugins/tmux-claude-ext/scripts/uninstall.sh
```

## License

MIT License - See LICENSE file for details

## Acknowledgments

- Inspired by the need to efficiently multitask with AI coding assistants
- Built for the tmux community
- Special thanks to Claude for being a great coding partner!

## Future Enhancements

- [ ] Go/Rust daemon for improved performance
- [ ] Machine learning for pattern detection
- [ ] Web dashboard for remote monitoring
- [ ] Integration with other AI coding assistants
- [ ] Historical analytics and usage patterns
- [ ] Mobile app notifications
- [ ] Collaborative session awareness

## Support

- **Issues**: [GitHub Issues](https://github.com/yourusername/tmux-claude-ext/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/tmux-claude-ext/discussions)
- **Wiki**: [Project Wiki](https://github.com/yourusername/tmux-claude-ext/wiki)

---

Made with ❤️ for developers who love tmux and Claude Code