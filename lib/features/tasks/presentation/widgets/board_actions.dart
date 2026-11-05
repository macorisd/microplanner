import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/data/workspace_controller.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../boards/data/models/board.dart';
import '../../../boards/providers/boards_provider.dart';
import 'action_confirmation_dialog.dart';
import 'board_editor_dialog.dart';

Future<void> editBoard(BuildContext context, Board board) async {
  if (context.read<WorkspaceController>().pendingBoardIds.contains(board.id)) {
    return;
  }
  await showMotionDialog<void>(
    context: context,
    builder: (_) => BoardEditorDialog(board: board),
  );
}

Future<void> confirmBoardDeletion(BuildContext context, Board board) async {
  final boards = context.read<BoardsProvider>();
  if (context.read<WorkspaceController>().pendingBoardIds.contains(board.id)) {
    return;
  }
  if (boards.boards.length <= 1) return;
  await showMotionDialog<void>(
    context: context,
    builder: (_) => ActionConfirmationDialog(
      title: 'Delete Board',
      actionLabel: 'Delete',
      pendingLabel: 'Deleting…',
      destructive: true,
      message:
          'Are you sure you want to delete "${board.name}"? This will also delete all subjects and tasks in this board.',
      onConfirm: () => boards.deleteBoard(board.id),
    ),
  );
}
