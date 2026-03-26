import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../util/constants.dart';

/// A prefix key configuration for the drawer.
class PrefixKeyConfig {
  final String label;
  final String description;
  final String sequence;

  const PrefixKeyConfig({
    required this.label,
    required this.description,
    required this.sequence,
  });
}

/// Default prefix key presets.
const latchPrefix = PrefixKeyConfig(
  label: 'Ctrl-]',
  description: 'latch',
  sequence: '\x1d',
);

const tmuxPrefix = PrefixKeyConfig(
  label: 'Ctrl-b',
  description: 'tmux',
  sequence: '\x02',
);

const screenPrefix = PrefixKeyConfig(
  label: 'Ctrl-a',
  description: 'screen',
  sequence: '\x01',
);

/// Slide-in drawer from the left edge with prefix key modifier buttons.
///
/// Swipe from the left edge to open. Tap a prefix key to send it to the
/// terminal. Swipe left or tap outside to dismiss.
class PrefixDrawer extends StatefulWidget {
  final void Function(String sequence) onSend;
  final Widget child;

  const PrefixDrawer({
    super.key,
    required this.onSend,
    required this.child,
  });

  @override
  State<PrefixDrawer> createState() => _PrefixDrawerState();
}

class _PrefixDrawerState extends State<PrefixDrawer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnim;
  bool _dragging = false;
  double _dragStartX = 0;

  static const _drawerWidth = 200.0;
  static const _edgeThreshold = 30.0;

  final _presets = const [latchPrefix, tmuxPrefix, screenPrefix];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _slideAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  void _open() {
    _controller.forward();
  }

  void _close() {
    _controller.reverse();
  }

  bool get _isOpen => _controller.value > 0.5;

  @override
  Widget build(BuildContext context) {
    final animValue = _slideAnim.value;

    return GestureDetector(
      onHorizontalDragStart: (details) {
        final x = details.globalPosition.dx;
        if (x < _edgeThreshold || _isOpen) {
          _dragging = true;
          _dragStartX = x;
        }
      },
      onHorizontalDragUpdate: (details) {
        if (!_dragging) return;
        final dx = details.globalPosition.dx - _dragStartX;
        if (_isOpen) {
          final val = 1.0 + (dx / _drawerWidth);
          _controller.value = val.clamp(0.0, 1.0);
        } else {
          final val = dx / _drawerWidth;
          _controller.value = val.clamp(0.0, 1.0);
        }
      },
      onHorizontalDragEnd: (details) {
        if (!_dragging) return;
        _dragging = false;
        if (_controller.value > 0.4) {
          _open();
        } else {
          _close();
        }
      },
      child: Stack(
        children: [
          widget.child,
          // Scrim
          if (animValue > 0)
            GestureDetector(
              onTap: _close,
              child: Container(
                color: Colors.black.withValues(alpha: 0.4 * animValue),
              ),
            ),
          // Drawer
          Positioned(
            left: -_drawerWidth + (_drawerWidth * animValue),
            top: 0,
            bottom: 0,
            width: _drawerWidth,
            child: _buildDrawerContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerContent() {
    return Container(
      decoration: const BoxDecoration(
        color: bgCard,
        border: Border(
          right: BorderSide(color: Color(0xFF2a2a3c), width: 1),
        ),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text(
                'Prefix Keys',
                style: TextStyle(
                  color: textDim,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                'Tap to send the prefix key',
                style: TextStyle(color: Colors.white30, fontSize: 12),
              ),
            ),
            for (final preset in _presets) _buildPrefixButton(preset),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Text(
                'Common Sequences',
                style: TextStyle(
                  color: textDim,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            _buildSequenceButton('Detach (latch)', '\x1dd'),
            _buildSequenceButton('New window (latch)', '\x1dc'),
            _buildSequenceButton('Detach (tmux)', '\x02d'),
            _buildSequenceButton('New window (tmux)', '\x02c'),
          ],
        ),
      ),
    );
  }

  Widget _buildPrefixButton(PrefixKeyConfig config) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            HapticFeedback.lightImpact();
            widget.onSend(config.sequence);
            _close();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: bgButton,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF44AA99).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    config.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF5cddaa),
                      fontSize: 12,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  config.description,
                  style: const TextStyle(
                    color: textDim,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSequenceButton(String label, String sequence) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            HapticFeedback.lightImpact();
            widget.onSend(sequence);
            _close();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Text(
              label,
              style: const TextStyle(color: textMuted, fontSize: 13),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
