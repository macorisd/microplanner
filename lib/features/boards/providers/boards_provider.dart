import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../../core/data/workspace_controller.dart';
import '../data/models/board.dart';
import '../data/models/subject.dart';

class BoardsProvider extends ChangeNotifier {
  final WorkspaceController workspace;
  String? _currentBoardId;
  String? _subjectsBoardId;
  String? _owner;
  bool _showSubjectsView = false;
  BoardsProvider(this.workspace) {
    workspace.addListener(_changed);
  }
  List<Board> get boards => List.unmodifiable(workspace.snapshot.boards);
  List<Subject> get subjects => List.unmodifiable(workspace.snapshot.subjects);
  bool get isLoading => workspace.isLoading;
  bool get showSubjectsView => _showSubjectsView;
  String? get currentBoardId => boards.any((b) => b.id == _currentBoardId)
      ? _currentBoardId
      : boards.firstOrNull?.id;
  Board? get currentBoard =>
      boards.where((b) => b.id == currentBoardId).firstOrNull;
  List<Subject> get currentBoardSubjects => subjects
      .where((s) => s.boardId == (_subjectsBoardId ?? currentBoardId))
      .toList();
  String? get subjectsBoardName => boards
      .where((b) => b.id == (_subjectsBoardId ?? currentBoardId))
      .firstOrNull
      ?.name;
  void _changed() {
    if (_owner != workspace.ownerId) {
      _owner = workspace.ownerId;
      _currentBoardId = null;
      _subjectsBoardId = null;
      _showSubjectsView = false;
    }
    if (_subjectsBoardId != null &&
        !boards.any((b) => b.id == _subjectsBoardId)) {
      _subjectsBoardId = null;
      _showSubjectsView = false;
    }
    notifyListeners();
  }

  void selectBoard(String id) {
    _currentBoardId = id;
    _showSubjectsView = false;
    notifyListeners();
  }

  Future<bool> addBoard({String? name}) async {
    final board = Board.create(
      id: const Uuid().v4(),
      name: name ?? 'Board ${boards.length + 1}',
      sortOrder:
          boards.fold<int>(
            -1,
            (max, b) => b.sortOrder > max ? b.sortOrder : max,
          ) +
          1,
    );
    final owner = workspace.ownerId;
    final success = await workspace.mutate(
      (s) => s.copyWith(boards: [...s.boards, board]),
    );
    if (success && owner == workspace.ownerId) {
      _currentBoardId = board.id;
      notifyListeners();
    }
    return success;
  }

  Future<bool> updateBoard(Board board) => workspace.mutate(
    (s) => s.copyWith(
      boards: s.boards.map((b) => b.id == board.id ? board : b).toList(),
    ),
  );
  Future<bool> deleteBoard(String id) async {
    if (boards.length <= 1) return false;
    return workspace.mutate(
      (s) => s.copyWith(
        boards: s.boards.where((b) => b.id != id).toList(),
        subjects: s.subjects.where((sub) => sub.boardId != id).toList(),
        tasks: s.tasks.where((t) => t.boardId != id).toList(),
      ),
    );
  }

  Future<bool> reorderBoards(int oldIndex, int newIndex) =>
      workspace.mutate((s) {
        final ordered = [...s.boards];
        if (newIndex > oldIndex) newIndex--;
        ordered.insert(newIndex, ordered.removeAt(oldIndex));
        return s.copyWith(
          boards: [
            for (var i = 0; i < ordered.length; i++)
              ordered[i].copyWith(sortOrder: i),
          ],
        );
      });
  void toggleSubjectsView() {
    _showSubjectsView = !_showSubjectsView;
    if (!_showSubjectsView) _subjectsBoardId = null;
    notifyListeners();
  }

  void showSubjectsForBoard(String id) {
    _subjectsBoardId = id;
    _showSubjectsView = true;
    notifyListeners();
  }

  void hideSubjectsView() {
    _subjectsBoardId = null;
    _showSubjectsView = false;
    notifyListeners();
  }

  Future<bool> addSubject({required String name, int? color}) async {
    final boardId = _subjectsBoardId ?? currentBoardId;
    if (boardId == null) return false;
    return workspace.mutate(
      (s) => s.copyWith(
        subjects: [
          ...s.subjects,
          Subject(
            id: const Uuid().v4(),
            name: name,
            boardId: boardId,
            color: color ?? 0xffcccccc,
          ),
        ],
      ),
    );
  }

  Future<bool> updateSubject(Subject subject) => workspace.mutate(
    (s) => s.copyWith(
      subjects: s.subjects
          .map((item) => item.id == subject.id ? subject : item)
          .toList(),
    ),
  );
  Future<bool> deleteSubject(String id) => workspace.mutate(
    (s) => s.copyWith(
      subjects: s.subjects.where((item) => item.id != id).toList(),
      tasks: s.tasks
          .map((t) => t.subjectId == id ? t.copyWith(subjectId: null) : t)
          .toList(),
    ),
  );
  Subject? getSubjectById(String? id) =>
      subjects.where((s) => s.id == id).firstOrNull;
  @override
  void dispose() {
    workspace.removeListener(_changed);
    super.dispose();
  }
}
