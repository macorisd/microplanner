import 'package:flutter/foundation.dart';

/// Mock user representing an authenticated user
class MockUser {
  final String id;
  final String email;
  final String displayName;
  final String? photoUrl;

  const MockUser({
    required this.id,
    required this.email,
    required this.displayName,
    this.photoUrl,
  });
}

/// Mock authentication service for MVP
/// Will be replaced with Firebase Auth + Google Sign-In later
class AuthService extends ChangeNotifier {
  MockUser? _currentUser;
  bool _isLoading = false;

  MockUser? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isLoading => _isLoading;

  /// Simulates Google Sign-In
  /// In production, this will use FirebaseAuth and GoogleSignIn
  Future<bool> signInWithGoogle() async {
    _isLoading = true;
    notifyListeners();

    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 800));

    // Create mock user
    _currentUser = const MockUser(
      id: 'mock-user-001',
      email: 'student@example.com',
      displayName: 'Student',
      photoUrl: null,
    );

    _isLoading = false;
    notifyListeners();
    return true;
  }

  /// Signs out the current user
  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();

    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 300));

    _currentUser = null;

    _isLoading = false;
    notifyListeners();
  }
}
