import 'package:flutter/material.dart';

import '../../models/connection.dart';
import '../../util/constants.dart';

class ConnectionTile extends StatelessWidget {
  final Connection connection;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback? onResetHostKey;
  final Widget? trailing;

  const ConnectionTile({
    super.key,
    required this.connection,
    required this.onTap,
    required this.onDelete,
    required this.onEdit,
    this.onResetHostKey,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final isRelay = connection.type == ConnectionType.relay;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: borderColor, width: 1)),
        ),
        child: Row(
          children: [
            // Online dot
            Container(
              width: 8, height: 8,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isRelay ? accent : textMuted,
              ),
            ),
            // Name + destination
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    connection.label,
                    style: const TextStyle(color: textBright, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    connection.sessionName != null && connection.sessionName!.isNotEmpty
                        ? '${connection.destination} · ${connection.sessionName}'
                        : connection.destination,
                    style: const TextStyle(color: textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              trailing!,
              const SizedBox(width: 4),
            ],
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz, color: textMuted, size: 16),
              onSelected: (value) {
                switch (value) {
                  case 'edit': onEdit();
                  case 'delete': onDelete();
                  case 'reset_host_key': onResetHostKey?.call();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'edit', child: Text('edit')),
                if (onResetHostKey != null)
                  const PopupMenuItem(value: 'reset_host_key', child: Text('reset host key')),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('delete', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
