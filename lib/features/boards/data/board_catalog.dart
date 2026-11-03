import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

import 'type_list_replacement.dart';

/// Stable names are persisted instead of Flutter's platform-specific codepoints.
const boardIcons = <String, IconData>{
  'board': Icons.dashboard_rounded,
  'book': Icons.menu_book_rounded,
  'school': Icons.school_rounded,
  'science': Icons.science_rounded,
  'calculate': Icons.calculate_rounded,
  'language': Icons.language_rounded,
  'history': Icons.history_edu_rounded,
  'psychology': Icons.psychology_rounded,
  'code': Icons.code_rounded,
  'computer': Icons.computer_rounded,
  'bug': Icons.bug_report_rounded,
  'build': Icons.build_rounded,
  'test': Icons.fact_check_rounded,
  'document': Icons.description_rounded,
  'folder': Icons.folder_rounded,
  'work': Icons.work_rounded,
  'meeting': Icons.groups_rounded,
  'calendar': Icons.event_rounded,
  'check': Icons.check_circle_rounded,
  'list': Icons.checklist_rounded,
  'idea': Icons.lightbulb_rounded,
  'art': Icons.palette_rounded,
  'camera': Icons.photo_camera_rounded,
  'music': Icons.music_note_rounded,
  'home': Icons.home_rounded,
  'heart': Icons.favorite_rounded,
  'health': Icons.health_and_safety_rounded,
  'fitness': Icons.fitness_center_rounded,
  'shopping': Icons.shopping_bag_rounded,
  'money': Icons.account_balance_wallet_rounded,
  'travel': Icons.flight_rounded,
  'nature': Icons.park_rounded,
  'star': Icons.star_rounded,
  'flag': Icons.flag_rounded,
  'reading': Icons.auto_stories_rounded,
  'presentation': Icons.slideshow_rounded,
  'quiz': Icons.quiz_rounded,
  'search': Icons.search_rounded,
  'edit': Icons.edit_rounded,
  'more': Icons.more_horiz_rounded,
};

final boardColors = List<int>.unmodifiable(
  AppColors.subjectColors.map((color) => color.toARGB32()),
);

/// Prefer white where readable, retaining the exact selected background color.
Color boardRowForeground(Color background) =>
    1.05 / (background.computeLuminance() + .05) >= 4.5
    ? Colors.white
    : Colors.black;

class InitialTypeList {
  const InitialTypeList(this.name, this.types);
  final String name;
  final List<TypeListEntry> types;
}

const initialTypeLists = <InitialTypeList>[
  InitialTypeList('Academic tasks', [
    TypeListEntry(name: 'Homework', icon: 'book'),
    TypeListEntry(name: 'Test', icon: 'quiz'),
    TypeListEntry(name: 'Presentation', icon: 'presentation'),
    TypeListEntry(name: 'Project', icon: 'folder'),
    TypeListEntry(name: 'Reading', icon: 'reading'),
    TypeListEntry(name: 'Other', icon: 'more'),
  ]),
  InitialTypeList('Software development', [
    TypeListEntry(name: 'Feature', icon: 'code'),
    TypeListEntry(name: 'Bug', icon: 'bug'),
    TypeListEntry(name: 'Refactor', icon: 'build'),
    TypeListEntry(name: 'Testing', icon: 'test'),
    TypeListEntry(name: 'Documentation', icon: 'document'),
    TypeListEntry(name: 'Review', icon: 'search'),
  ]),
  InitialTypeList('Work', [
    TypeListEntry(name: 'Meeting', icon: 'meeting'),
    TypeListEntry(name: 'Report', icon: 'document'),
    TypeListEntry(name: 'Research', icon: 'search'),
    TypeListEntry(name: 'Planning', icon: 'calendar'),
    TypeListEntry(name: 'Follow-up', icon: 'check'),
    TypeListEntry(name: 'Other', icon: 'more'),
  ]),
  InitialTypeList('Personal life', [
    TypeListEntry(name: 'Errand', icon: 'shopping'),
    TypeListEntry(name: 'Appointment', icon: 'calendar'),
    TypeListEntry(name: 'Household', icon: 'home'),
    TypeListEntry(name: 'Health', icon: 'health'),
    TypeListEntry(name: 'Finance', icon: 'money'),
    TypeListEntry(name: 'Other', icon: 'more'),
  ]),
  InitialTypeList('Creative projects', [
    TypeListEntry(name: 'Idea', icon: 'idea'),
    TypeListEntry(name: 'Research', icon: 'search'),
    TypeListEntry(name: 'Draft', icon: 'edit'),
    TypeListEntry(name: 'Design', icon: 'art'),
    TypeListEntry(name: 'Review', icon: 'search'),
    TypeListEntry(name: 'Finalize', icon: 'check'),
  ]),
];
