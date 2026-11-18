import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../core/data/api_client.dart';
import '../../../../core/data/workspace_controller.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/widgets/form_message.dart';
import '../../../auth/data/auth_service.dart';
import 'form_dialog.dart';

class AccountDeletionPage extends StatefulWidget {
  const AccountDeletionPage({super.key});

  @override
  State<AccountDeletionPage> createState() => _AccountDeletionPageState();
}

class _AccountDeletionPageState extends State<AccountDeletionPage> {
  bool _open = false;

  Future<void> _confirm(AuthService auth, AppUser user) async {
    if (_open) return;
    _open = true;
    if (context.read<WorkspaceController>().isOnline) {
      unawaited(auth.refreshDeletionAvailability());
    }
    try {
      await showMotionDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _DeleteAccountDialog(auth: auth, user: user),
      );
    } finally {
      _open = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;
    if (user == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(user.displayName, style: Theme.of(context).textTheme.titleMedium),
        Text(user.email),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            onPressed: () => _confirm(auth, user),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Delete account'),
          ),
        ),
      ],
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.auth, required this.user});

  final AuthService auth;
  final AppUser user;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  bool _verifying = false;
  bool _deleting = false;
  String? _grant;
  String? _error;

  Future<void> _proceed() async {
    if (_verifying || _deleting) return;
    final auth = widget.auth;
    final grant = _grant;
    setState(() {
      _error = null;
      _verifying = grant == null;
      _deleting = grant != null;
    });
    try {
      if (grant == null) {
        final verified = await auth.verifyDeletion(widget.user.id);
        if (mounted) {
          setState(() {
            _grant = verified;
            if (verified == null) _error = 'Google verification was cancelled.';
          });
        }
      } else {
        final deleted = await auth.deleteAccount(widget.user.id, grant);
        if (!mounted) return;
        if (auth.recoveringDeletion || deleted) {
          Navigator.of(context).pop();
          return;
        }
        setState(() {
          _grant = null;
          _error = auth.error ?? 'Could not delete your account. Try again.';
        });
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not continue. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _verifying = false;
          _deleting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    if (_verifying) widget.auth.google.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final online = context.watch<WorkspaceController>().isOnline;
    final auth = context.watch<AuthService>();
    final verified = _grant != null;
    final availability = !online
        ? 'Connect to the internet to delete your account.'
        : !auth.canVerifyDeletion
        ? 'Account deletion is currently unavailable.'
        : null;
    final status = _deleting
        ? 'Deleting your account…'
        : _verifying
        ? 'Waiting for Google verification…'
        : verified
        ? 'Google account verified. Select Delete to permanently delete your account.'
        : null;
    return PopScope(
      canPop: !_deleting,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (!_deleting) Navigator.of(context).pop();
          },
        },
        child: FormDialog(
          title: const Text('Delete account'),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.user.email,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'This permanently deletes your microplanner account, boards, '
                'tasks, settings and unsynced changes. It cannot be undone. '
                'Your Google account stays active.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Other devices lose cloud access immediately. Cached data and '
                'scheduled reminders may remain until those devices reconnect '
                'with an up-to-date app.',
              ),
              Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: Theme.of(context).colorScheme.copyWith(
                    error: _error != null || availability != null
                        ? Colors.red.shade700
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                child: FormMessage(message: _error ?? availability ?? status),
              ),
            ],
          ),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: _deleting ? null : () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: availability != null || _verifying || _deleting
                  ? null
                  : _proceed,
              style: verified
                  ? FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                    )
                  : null,
              child: Text(verified ? 'Delete' : 'Verify with Google'),
            ),
          ],
        ),
      ),
    );
  }
}
