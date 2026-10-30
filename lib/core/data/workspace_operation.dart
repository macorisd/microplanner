import 'workspace_delta.dart';

/// A persisted intent and, once sent, its exact retryable request body.
/// Tokens never enter this record; each attempt uses the current same-owner session.
class WorkspaceOperation {
  final String id;
  WorkspaceDelta delta;
  final DateTime createdAt;
  final String? sourceId;
  final Map<String, dynamic>? importData;
  Map<String, dynamic>? request;
  bool uncertain;
  String? failure;
  int conflicts;

  WorkspaceOperation({
    required this.id,
    required this.delta,
    required this.createdAt,
    this.sourceId,
    this.importData,
    this.request,
    this.uncertain = false,
    this.failure,
    this.conflicts = 0,
  });

  factory WorkspaceOperation.fromJson(Map<String, dynamic> json) =>
      WorkspaceOperation(
        id: json['id'] as String,
        delta: WorkspaceDelta.fromJson(
          Map<String, dynamic>.from(json['delta'] as Map),
        ),
        createdAt: DateTime.parse(json['createdAt'] as String),
        sourceId: json['sourceId'] as String?,
        importData: json['importData'] == null
            ? null
            : Map<String, dynamic>.from(json['importData'] as Map),
        request: json['request'] == null
            ? null
            : Map<String, dynamic>.from(json['request'] as Map),
        uncertain: json['uncertain'] as bool? ?? false,
        failure: json['failure'] as String?,
        conflicts: json['conflicts'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'delta': delta.toJson(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'sourceId': sourceId,
    'importData': importData,
    'request': request,
    'uncertain': uncertain,
    'failure': failure,
    'conflicts': conflicts,
  };
}
