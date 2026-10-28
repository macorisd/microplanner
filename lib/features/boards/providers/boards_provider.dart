import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../../core/data/workspace_controller.dart';
import '../../../core/data/same_list.dart';
import '../data/models/board.dart';
import '../data/models/subject.dart';
import '../data/board_selection_storage.dart';

class BoardsProvider extends ChangeNotifier {
  final WorkspaceController workspace;
  final BoardSelectionStorage? selectionStorage;
  String? _currentBoardId;
  String? _subjectsBoardId;
  String? _owner;
  bool _showSubjectsView = false;
  List<Board> _boards = const [];
  List<Subject> _subjects = const [];
  Map<String, Board> _boardIndex = {};
  Map<String, Subject> _subjectIndex = {};
  Map<String, List<Subject>> _subjectsByBoard = {};
  final _selectionWrites = <String, Future<void>>{};
  String? _preferredBoardId;
  int _selectionGeneration = 0;
  int _selectionVersion = 0;
  bool _selectionLoaded = true;
  bool _preferenceAvailable = true;
  bool _confirmed = false;
  BoardsProvider(this.workspace, {this.selectionStorage}) {
    workspace.addListener(_changed);
    _changed();
  }
  List<Board> get boards => _boards;
  List<Subject> get subjects => _subjects;
  bool get isLoading => workspace.isLoading;
  bool get showSubjectsView => _showSubjectsView;
  bool get isRestoringSelection => !_selectionLoaded;
  String? get currentBoardId =>
      _selectionLoaded ? _currentBoardId ?? _boards.firstOrNull?.id : null;
  Board? get currentBoard => _boardIndex[currentBoardId];
  List<Subject> get currentBoardSubjects =>
      _subjectsByBoard[_subjectsBoardId ?? currentBoardId] ?? const [];
  String? get subjectsBoardName =>
      _boardIndex[_subjectsBoardId ?? currentBoardId]?.name;
  void _changed() {
    final previousSelection = _currentBoardId;
    final ownerChanged = _owner != workspace.ownerId;
    final data = workspace.snapshot;
    final boardsChanged = !sameList(
      _boards,
      data.boards,
      (a, b) =>
          a.id == b.id &&
          a.name == b.name &&
          a.createdAt == b.createdAt &&
          a.sortOrder == b.sortOrder,
    );
    final subjectsChanged = !sameList(
      _subjects,
      data.subjects,
      (a, b) =>
          a.id == b.id &&
          a.name == b.name &&
          a.boardId == b.boardId &&
          a.color == b.color,
    );
    final confirmed =
        workspace.hasData && workspace.isOnline && !workspace.isLoading;
    final confirmationChanged = _confirmed != confirmed;
    _confirmed = confirmed;
    if (!ownerChanged &&
        !boardsChanged &&
        !subjectsChanged &&
        !confirmationChanged) {
      return;
    }
    if (ownerChanged) {
      _owner = workspace.ownerId;
      _currentBoardId = null;
      _subjectsBoardId = null;
      _showSubjectsView = false;
      _preferredBoardId = null;
      ++_selectionGeneration;
      _selectionVersion = 0;
      _preferenceAvailable = true;
      _selectionLoaded = selectionStorage == null || _owner == null;
      if (!_selectionLoaded) {
        unawaited(_restoreSelection(_owner!, _selectionGeneration));
      }
    }
    if (boardsChanged || ownerChanged) {
      _boards = List.unmodifiable(data.boards);
      _boardIndex = {for (final board in _boards) board.id: board};
    }
    if (subjectsChanged || ownerChanged) {
      _subjects = List.unmodifiable(data.subjects);
      _subjectIndex = {for (final subject in _subjects) subject.id: subject};
      final grouped = <String, List<Subject>>{};
      for (final subject in _subjects) {
        grouped.putIfAbsent(subject.boardId, () => []).add(subject);
      }
      _subjectsByBoard = grouped.map(
        (id, items) => MapEntry(id, List.unmodifiable(items)),
      );
    }
    _resolveSelection();
    if (_subjectsBoardId != null &&
        !boards.any((b) => b.id == _subjectsBoardId)) {
      _subjectsBoardId = null;
      _showSubjectsView = false;
    }
    if (ownerChanged ||
        boardsChanged ||
        subjectsChanged ||
        previousSelection != _currentBoardId) {
      notifyListeners();
    }
  }

  Future<void> _restoreSelection(String owner, int generation) async {
    final version = _selectionVersion;
    String? saved;
    var available = true;
    try {
      await _selectionWrites[owner]?.timeout(const Duration(seconds: 2));
      saved = await selectionStorage!
          .read(owner)
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      available = false;
      // A preference failure must not block access to workspace data.
    }
    if (generation != _selectionGeneration || owner != _owner) return;
    if (version == _selectionVersion) {
      _preferredBoardId = saved;
      _preferenceAvailable = available;
    }
    _selectionLoaded = true;
    _resolveSelection();
    notifyListeners();
  }

  void _resolveSelection() {
    if (!_selectionLoaded) return;
    if (_boardIndex.containsKey(_preferredBoardId)) {
      _currentBoardId = _preferredBoardId;
    } else if (!_boardIndex.containsKey(_currentBoardId)) {
      _currentBoardId = _boards.firstOrNull?.id;
    }
    if (_confirmed &&
        _preferenceAvailable &&
        _currentBoardId != null &&
        _preferredBoardId != _currentBoardId) {
      _remember(_currentBoardId!);
    }
  }

  void _remember(String id) {
    _preferredBoardId = id;
    final owner = _owner;
    final storage = selectionStorage;
    if (owner == null || storage == null) return;
    final previous = _selectionWrites[owner] ?? Future<void>.value();
    // Preserve every account's final selection even when it is signing out.
    _selectionWrites[owner] = previous
        .then((_) => storage.write(owner, id))
        .catchError((Object _) {});
  }

  void selectBoard(String id) {
    if (!_boardIndex.containsKey(id) ||
        (_currentBoardId == id && !_showSubjectsView)) {
      return;
    }
    _currentBoardId = id;
    _selectionLoaded = true;
    _preferenceAvailable = true;
    ++_selectionVersion;
    _remember(id);
    _showSubjectsView = false;
    notifyListeners();
  }

  Future<bool> addBoard({String? name}) async {
    final id = const Uuid().v4();
    final owner = workspace.ownerId;
    final success = await workspace.mutate(
      (s) => s.copyWith(
        boards: [
          ...s.boards,
          Board.create(
            id: id,
            name: name ?? 'Board ${s.boards.length + 1}',
            sortOrder:
                s.boards.fold<int>(
                  -1,
                  (max, b) => b.sortOrder > max ? b.sortOrder : max,
                ) +
                1,
          ),
        ],
      ),
    );
    if (success && owner == workspace.ownerId) {
      selectBoard(id);
    }
    return success;
  }

  Future<bool> updateBoard(Board board) => workspace.mutate(
    (s) => !s.boards.any((b) => b.id == board.id)
        ? null
        : s.copyWith(
            boards: s.boards.map((b) => b.id == board.id ? board : b).toList(),
          ),
  );
  Future<bool> deleteBoard(String id) async {
    if (boards.length <= 1) return false;
    return workspace.mutate(
      (s) => s.boards.length <= 1
          ? null
          : s.copyWith(
              boards: s.boards.where((b) => b.id != id).toList(),
              subjects: s.subjects.where((sub) => sub.boardId != id).toList(),
              tasks: s.tasks.where((t) => t.boardId != id).toList(),
            ),
    );
  }

  Future<bool> reorderBoards(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= boards.length ||
        newIndex < 0 ||
        newIndex > boards.length) {
      return Future.value(false);
    }
    final moved = boards[oldIndex].id;
    final before = newIndex < boards.length ? boards[newIndex].id : null;
    return workspace.mutate((s) {
      final ordered = [...s.boards];
      final from = ordered.indexWhere((board) => board.id == moved);
      if (from < 0) return null;
      final board = ordered.removeAt(from);
      final target = before == null
          ? ordered.length
          : ordered.indexWhere((board) => board.id == before);
      if (before == moved) return s;
      if (target < 0) return null;
      ordered.insert(target, board);
      return s.copyWith(
        boards: [
          for (var i = 0; i < ordered.length; i++)
            ordered[i].copyWith(sortOrder: i),
        ],
      );
    });
  }

  void toggleSubjectsView() {
    _showSubjectsView = !_showSubjectsView;
    if (!_showSubjectsView) _subjectsBoardId = null;
    notifyListeners();
  }

  void showSubjectsForBoard(String id) {
    if (_showSubjectsView && _subjectsBoardId == id) return;
    _subjectsBoardId = id;
    _showSubjectsView = true;
    notifyListeners();
  }

  void hideSubjectsView() {
    if (!_showSubjectsView) return;
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
    (s) => !s.subjects.any((item) => item.id == subject.id)
        ? null
        : s.copyWith(
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
  Subject? getSubjectById(String? id) => _subjectIndex[id];
  @override
  void dispose() {
    ++_selectionGeneration;
    workspace.removeListener(_changed);
    super.dispose();
  }
}
