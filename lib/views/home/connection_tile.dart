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

    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      color: bgCard,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: isRelay ? accent.withValues(alpha: 0.12) : bgSurface,
          ),
          child: Icon(
            isRelay ? Icons.cloud_outlined : Icons.terminal,
            color: isRelay ? accent : textDim,
            size: 18,
          ),
        ),
        title: Text(
          connection.label,
          style: const TextStyle(
            fontFamily: 'monospace',
            color: textBright,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          connection.sessionName != null && connection.sessionName!.isNotEmpty
              ? '${connection.destination} · ${connection.sessionName}'
              : connection.destination,
          style: const TextStyle(fontFamily: 'monospace', color: textMuted, fontSize: 11),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (trailing != null) ...[
              trailing!,
              const SizedBox(width: 4),
            ],
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: textMuted, size: 18),
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    onEdit();
                  case 'delete':
                    onDelete();
                  case 'reset_host_key':
                    onResetHostKey?.call();
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
        onTap: onTap,
      ),
    );
  }
}
