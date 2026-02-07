import 'package:flutter/material.dart';

/// Task types available in MicroPlanner
enum TaskType {
  unassigned('No type', Icons.remove_rounded),
  homework('Homework', Icons.menu_book_rounded),
  test('Test', Icons.quiz_rounded),
  presentation('Presentation', Icons.slideshow_rounded),
  project('Project', Icons.folder_rounded),
  reading('Reading', Icons.auto_stories_rounded),
  other('Other', Icons.more_horiz_rounded);

  const TaskType(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Task priority levels
enum TaskPriority {
  low('Low'),
  medium('Medium'),
  high('High');

  const TaskPriority(this.label);
  final String label;
}
