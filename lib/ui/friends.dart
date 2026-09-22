import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/social.dart';

class FriendsSheet extends StatefulWidget {
  final SocialService social;
  final String? roomCode;
  final Future<void> Function(String code) join;
  const FriendsSheet({
    super.key,
    required this.social,
    required this.roomCode,
    required this.join,
  });
  @override
  State<FriendsSheet> createState() => _FriendsSheetState();
}

class _FriendsSheetState extends State<FriendsSheet> {
  final id = TextEditingController();
  List<dynamic> friends = [], invites = [];
  bool busy = false;
  String message = '';
  Timer? refreshTimer;
  @override
  void initState() {
    super.initState();
    refresh();
    refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!busy) unawaited(refresh());
    });
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    id.dispose();
    super.dispose();
  }

  Future<void> action(Future<void> Function() work) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await work();
    } catch (e) {
      message = e.toString();
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> refresh() => action(() async {
    friends = (await widget.social.call('friends'))['friends'] as List;
    invites = (await widget.social.call('invitations'))['invitations'] as List;
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      16,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 16,
    ),
    child: ListView(
      shrinkWrap: true,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Friends & invites',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              onPressed: busy ? null : refresh,
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (widget.social.store.cloud)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('My player ID'),
            subtitle: SelectableText(widget.social.store.uid),
            trailing: IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copy ID',
              onPressed: () => Clipboard.setData(
                ClipboardData(text: widget.social.store.uid),
              ),
            ),
          ),
        TextField(
          controller: id,
          decoration: const InputDecoration(
            labelText: 'Friend’s player ID',
            border: OutlineInputBorder(),
          ),
        ),
        FilledButton.icon(
          onPressed: busy
              ? null
              : () => action(() async {
                  friends =
                      (await widget.social.call('friends', {
                            'action': 'add',
                            'id': id.text.trim(),
                          }))['friends']
                          as List;
                  message = 'Friend request sent';
                  id.clear();
                }),
          icon: const Icon(Icons.person_add),
          label: const Text('Add friend'),
        ),
        if (busy) const LinearProgressIndicator(),
        if (message.isNotEmpty) Text(message),
        if (invites.isNotEmpty)
          const Text(
            'Room invitations',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ...invites.map(
          (p) => ListTile(
            title: Text('${p['name']} invited you'),
            subtitle: Text('Room ${p['code']}'),
            trailing: TextButton(
              onPressed: busy
                  ? null
                  : () => action(() async {
                      await widget.join(p['code'] as String);
                      await widget.social.call('invitations', {
                        'action': 'dismiss',
                        'id': p['from'],
                      });
                      if (context.mounted) Navigator.pop(context);
                    }),
              child: const Text('Join'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (friends.isEmpty && !busy)
          const Text(
            'Add a friend by ID. Accept their request to exchange room invitations.',
          ),
        ...friends.map(
          (p) => ListTile(
            title: Text(p['name'] as String),
            subtitle: Text(
              p['status'] == 'accepted'
                  ? 'Friend'
                  : p['incoming'] == true
                  ? 'Wants to be your friend'
                  : 'Request sent',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (p['status'] == 'pending' && p['incoming'] == true)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => action(() async {
                            friends =
                                (await widget.social.call('friends', {
                                      'action': 'accept',
                                      'id': p['id'],
                                    }))['friends']
                                    as List;
                          }),
                    child: const Text('Accept'),
                  ),
                if (p['status'] == 'accepted' && widget.roomCode != null)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => action(() async {
                            await widget.social.call('invitations', {
                              'action': 'send',
                              'id': p['id'],
                              'code': widget.roomCode,
                            });
                            message = 'Invitation sent';
                          }),
                    child: const Text('Invite'),
                  ),
                IconButton(
                  tooltip: 'Remove or decline',
                  icon: const Icon(Icons.close),
                  onPressed: busy
                      ? null
                      : () => action(() async {
                          friends =
                              (await widget.social.call('friends', {
                                    'action': 'remove',
                                    'id': p['id'],
                                  }))['friends']
                                  as List;
                        }),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}
