import 'ui_sounds.dart';
import 'cartoon_controls.dart';

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
      message = friendlyOnlineError(e);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> refresh() => action(() async {
    friends = await widget.social.fetchFriends();
    invites = await widget.social.fetchInvites();
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
              onPressed: UiSounds.wrap(busy ? null : refresh),
              tooltip: 'Refresh',
              icon: const CartoonIcon(Icons.refresh),
            ),
          ],
        ),
        if (widget.social.store.cloud)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('My player ID'),
            subtitle: SelectableText(
              widget.social.store.uidOrNull ?? 'Signing in…',
            ),
            trailing: IconButton(
              icon: const CartoonIcon(Icons.copy),
              tooltip: 'Copy ID',
              onPressed: () {
                final id = widget.social.store.uidOrNull;
                if (id != null) Clipboard.setData(ClipboardData(text: id));
              },
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
          onPressed: UiSounds.wrap(
            busy
                ? null
                : () => action(() async {
                    final outcome = await widget.social.addFriend(id.text);
                    friends = await widget.social.fetchFriends();
                    message = outcome == 'accepted'
                        ? 'Friend added'
                        : 'Friend request sent';
                    id.clear();
                  }),
          ),
          icon: const CartoonIcon(Icons.person_add),
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
              onPressed: UiSounds.wrap(
                busy
                    ? null
                    : () => action(() async {
                        await widget.join(p['code'] as String);
                        await widget.social.dismissInvite(p['from'].toString());
                        if (context.mounted) Navigator.pop(context);
                      }),
              ),
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
                    onPressed: UiSounds.wrap(
                      busy
                          ? null
                          : () => action(() async {
                              await widget.social.acceptFriend(
                                p['id'].toString(),
                              );
                              friends = await widget.social.fetchFriends();
                            }),
                    ),
                    child: const Text('Accept'),
                  ),
                if (p['status'] == 'accepted' && widget.roomCode != null)
                  TextButton(
                    onPressed: UiSounds.wrap(
                      busy
                          ? null
                          : () => action(() async {
                              await widget.social.sendInvite(
                                p['id'].toString(),
                                widget.roomCode!,
                              );
                              message = 'Invitation sent';
                            }),
                    ),
                    child: const Text('Invite'),
                  ),
                IconButton(
                  tooltip: 'Remove or decline',
                  icon: const CartoonIcon(Icons.close),
                  onPressed: UiSounds.wrap(
                    busy
                        ? null
                        : () => action(() async {
                            await widget.social.removeFriend(
                              p['id'].toString(),
                            );
                            friends = await widget.social.fetchFriends();
                          }),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: UiSounds.wrap(() => Navigator.pop(context)),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}
