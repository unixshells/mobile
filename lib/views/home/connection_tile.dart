import 'package:flutter/material.dart';

import '../../models/connection.dart';
import '../../util/constants.dart';

class ConnectionTile extends StatelessWidget {
  final Connection connection;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final Widget? trailing;

  const ConnectionTile({
    super.key,
    required this.connection,
    required this.onTap,
    required this.onDelete,
    required this.onEdit,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final isRelay = connection.type == ConnectionType.relay;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor:
            isRelay ? Colors.blue.withValues(alpha: 0.2) : bgButton,
        child: Icon(
          isRelay ? Icons.cloud : Icons.computer,
          color: isRelay ? Colors.blue : Colors.white54,
          size: 20,
        ),
      ),
      title: Text(
        connection.label,
        style: const TextStyle(color: Colors.white, fontSize: 15),
      ),
      subtitle: Text(
        connection.sessionName != null && connection.sessionName!.isNotEmpty
            ? '${connection.destination} · ${connection.sessionName}'
            : connection.destination,
        style: const TextStyle(color: Colors.white38, fontSize: 13),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailing != null) ...[
            trailing!,
            const SizedBox(width: 8),
          ],
          PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, color: Colors.white38),
        color: bgCard,
        onSelected: (value) {
          switch (value) {
            case 'edit':
              onEdit();
            case 'delete':
              onDelete();
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'edit',
            child: Text('Edit', style: TextStyle(color: Colors.white)),
          ),
          const PopupMenuItem(
            value: 'delete',
            child: Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}
