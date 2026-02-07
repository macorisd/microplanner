import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../data/models/board.dart';
import '../data/models/subject.dart';

/// Provider for board and subject management with Hive persistence
class BoardsProvider extends ChangeNotifier {
  static const String _boardsBoxName = 'boards';
  static const String _subjectsBoxName = 'subjects';
  static const String _defaultBoardId = 'default-board';
  
  final Uuid _uuid = const Uuid();
  
  Box<Board>? _boardsBox;
  Box<Subject>? _subjectsBox;
  List<Board> _boards = [];
  List<Subject> _subjects = [];
  String? _currentBoardId;
  String? _subjectsBoardId; // Board ID for subjects view (may differ from current)
  bool _isLoading = false;
  bool _showSubjectsView = false;

  List<Board> get boards => _boards;
  List<Subject> get subjects => _subjects;
  bool get isLoading => _isLoading;
  bool get showSubjectsView => _showSubjectsView;
  
  String? get currentBoardId => _currentBoardId;
  
  Board? get currentBoard {
    if (_currentBoardId == null) return null;
    try {
      return _boards.firstWhere((b) => b.id == _currentBoardId);
    } catch (_) {
      return null;
    }
  }

  /// Subjects for the board being viewed in subjects panel
  List<Subject> get currentBoardSubjects {
    final boardId = _subjectsBoardId ?? _currentBoardId;
    if (boardId == null) return [];
    return _subjects.where((s) => s.boardId == boardId).toList();
  }

  /// Name of board being viewed in subjects panel
  String? get subjectsBoardName {
    final boardId = _subjectsBoardId ?? _currentBoardId;
    if (boardId == null) return null;
    try {
      return _boards.firstWhere((b) => b.id == boardId).name;
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Initialization
  // ─────────────────────────────────────────────────────────────────────────
  
  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    try {
      _boardsBox = await Hive.openBox<Board>(_boardsBoxName);
      _subjectsBox = await Hive.openBox<Subject>(_subjectsBoxName);
      _loadBoards();
      _loadSubjects();
      
      // Create default board if none exist
      if (_boards.isEmpty) {
        await _createDefaultBoard();
        _loadBoards(); // Reload after creating default
      }
      
      // Always set current board to first one if not set
      if (_boards.isNotEmpty) {
        _currentBoardId = _boards.first.id;
      }
    } catch (e) {
      debugPrint('Error initializing boards: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _createDefaultBoard() async {
    final defaultBoard = Board.create(
      id: _defaultBoardId,
      name: 'Board 1',
    );
    await _boardsBox?.put(defaultBoard.id, defaultBoard);
    _loadBoards();
  }

  void _loadBoards() {
    if (_boardsBox != null) {
      _boards = _boardsBox!.values.toList();
      // Sort by sortOrder (ascending), then by createdAt as fallback
      _boards.sort((a, b) {
        final orderCompare = a.sortOrder.compareTo(b.sortOrder);
        if (orderCompare != 0) return orderCompare;
        return a.createdAt.compareTo(b.createdAt);
      });
    }
  }

  void _loadSubjects() {
    if (_subjectsBox != null) {
      _subjects = _subjectsBox!.values.toList();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Board Operations
  // ─────────────────────────────────────────────────────────────────────────

  void selectBoard(String boardId) {
    _currentBoardId = boardId;
    _showSubjectsView = false;
    notifyListeners();
  }

  Future<void> addBoard({String? name}) async {
    final boardNumber = _boards.length + 1;
    // Set sortOrder to be after all existing boards
    final maxSortOrder = _boards.isEmpty 
        ? 0 
        : _boards.map((b) => b.sortOrder).reduce((a, b) => a > b ? a : b);
    final board = Board.create(
      id: _uuid.v4(),
      name: name ?? 'Board $boardNumber',
      sortOrder: maxSortOrder + 1,
    );
    
    await _boardsBox?.put(board.id, board);
    _loadBoards();
    _currentBoardId = board.id;
    notifyListeners();
  }

  Future<void> updateBoard(Board board) async {
    await _boardsBox?.put(board.id, board);
    _loadBoards();
    notifyListeners();
  }

  Future<void> deleteBoard(String boardId) async {
    // Don't allow deleting the last board
    if (_boards.length <= 1) return;
    
    // Delete all subjects in this board
    final boardSubjects = _subjects.where((s) => s.boardId == boardId).toList();
    for (final subject in boardSubjects) {
      await _subjectsBox?.delete(subject.id);
    }
    
    await _boardsBox?.delete(boardId);
    _loadBoards();
    _loadSubjects();
    
    // Switch to another board if current was deleted
    if (_currentBoardId == boardId && _boards.isNotEmpty) {
      _currentBoardId = _boards.first.id;
    }
    
    notifyListeners();
  }

  /// Reorder boards by moving a board from oldIndex to newIndex
  Future<void> reorderBoards(int oldIndex, int newIndex) async {
    // Adjust for ReorderableListView behavior
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    
    // Move the board in the list
    final board = _boards.removeAt(oldIndex);
    _boards.insert(newIndex, board);
    
    // Update sortOrder for all boards
    for (int i = 0; i < _boards.length; i++) {
      final updatedBoard = _boards[i].copyWith(sortOrder: i);
      await _boardsBox?.put(updatedBoard.id, updatedBoard);
    }
    
    _loadBoards();
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Subject Operations
  // ─────────────────────────────────────────────────────────────────────────

  void toggleSubjectsView() {
    _showSubjectsView = !_showSubjectsView;
    if (!_showSubjectsView) {
      _subjectsBoardId = null;
    }
    notifyListeners();
  }

  void showSubjectsForBoard(String boardId) {
    _subjectsBoardId = boardId;
    _showSubjectsView = true;
    notifyListeners();
  }

  void hideSubjectsView() {
    _showSubjectsView = false;
    _subjectsBoardId = null;
    notifyListeners();
  }

  Future<void> addSubject({required String name, int? color}) async {
    final boardId = _subjectsBoardId ?? _currentBoardId;
    if (boardId == null) return;
    
    final subject = Subject(
      id: _uuid.v4(),
      name: name,
      boardId: boardId,
      color: color ?? 0xFFCCCCCC,
    );
    
    await _subjectsBox?.put(subject.id, subject);
    _loadSubjects();
    notifyListeners();
  }

  Future<void> updateSubject(Subject subject) async {
    await _subjectsBox?.put(subject.id, subject);
    _loadSubjects();
    notifyListeners();
  }

  Future<void> deleteSubject(String subjectId) async {
    await _subjectsBox?.delete(subjectId);
    _loadSubjects();
    notifyListeners();
  }

  /// Get subject by ID
  Subject? getSubjectById(String? id) {
    if (id == null) return null;
    try {
      return _subjects.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Cleanup
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> clearAll() async {
    await _boardsBox?.clear();
    await _subjectsBox?.clear();
    _loadBoards();
    _loadSubjects();
    notifyListeners();
  }
}
