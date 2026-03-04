import 'dart:convert';

class NotebookCategoryModel {
  final String id;
  final String title;
  final String collectionId;
  final DateTime createdAt;

  const NotebookCategoryModel({
    required this.id,
    required this.title,
    required this.collectionId,
    required this.createdAt,
  });

  NotebookCategoryModel copyWith({
    String? id,
    String? title,
    String? collectionId,
    DateTime? createdAt,
  }) {
    return NotebookCategoryModel(
      id: id ?? this.id,
      title: title ?? this.title,
      collectionId: collectionId ?? this.collectionId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'collectionId': collectionId,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory NotebookCategoryModel.fromJson(Map<String, dynamic> json) {
    return NotebookCategoryModel(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      collectionId: json['collectionId'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class NotebookModel {
  final String id;
  final String title;
  final String emoji;
  final String colorHex;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String defaultCollectionId;
  final List<NotebookCategoryModel> categories;

  const NotebookModel({
    required this.id,
    required this.title,
    required this.emoji,
    required this.colorHex,
    required this.createdAt,
    required this.updatedAt,
    required this.defaultCollectionId,
    required this.categories,
  });

  NotebookModel copyWith({
    String? id,
    String? title,
    String? emoji,
    String? colorHex,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? defaultCollectionId,
    List<NotebookCategoryModel>? categories,
  }) {
    return NotebookModel(
      id: id ?? this.id,
      title: title ?? this.title,
      emoji: emoji ?? this.emoji,
      colorHex: colorHex ?? this.colorHex,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      defaultCollectionId: defaultCollectionId ?? this.defaultCollectionId,
      categories: categories ?? this.categories,
    );
  }

  NotebookCategoryModel? findCategory(String categoryId) {
    for (final category in categories) {
      if (category.id == categoryId) return category;
    }
    return null;
  }

  NotebookCategoryModel? findCategoryByCollection(String collectionId) {
    for (final category in categories) {
      if (category.collectionId == collectionId) return category;
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'emoji': emoji,
      'colorHex': colorHex,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'defaultCollectionId': defaultCollectionId,
      'categories': categories.map((category) => category.toJson()).toList(),
    };
  }

  factory NotebookModel.fromJson(Map<String, dynamic> json) {
    final rawCategories = json['categories'] as List<dynamic>? ?? const [];

    return NotebookModel(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      emoji: json['emoji'] as String? ?? '',
      colorHex: json['colorHex'] as String? ?? '#334155',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      defaultCollectionId: json['defaultCollectionId'] as String? ?? '',
      categories: rawCategories
          .whereType<Map<String, dynamic>>()
          .map(NotebookCategoryModel.fromJson)
          .toList(),
    );
  }
}

class NotebookMigrationState {
  final bool completed;
  final String phase;
  final int cursor;
  final String? targetNotebookId;

  const NotebookMigrationState({
    required this.completed,
    required this.phase,
    required this.cursor,
    this.targetNotebookId,
  });

  static const NotebookMigrationState initial = NotebookMigrationState(
    completed: false,
    phase: 'copying',
    cursor: 0,
  );

  NotebookMigrationState copyWith({
    bool? completed,
    String? phase,
    int? cursor,
    String? targetNotebookId,
    bool clearTargetNotebookId = false,
  }) {
    return NotebookMigrationState(
      completed: completed ?? this.completed,
      phase: phase ?? this.phase,
      cursor: cursor ?? this.cursor,
      targetNotebookId: clearTargetNotebookId
          ? null
          : (targetNotebookId ?? this.targetNotebookId),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'completed': completed,
      'phase': phase,
      'cursor': cursor,
      'targetNotebookId': targetNotebookId,
    };
  }

  factory NotebookMigrationState.fromJson(Map<String, dynamic> json) {
    return NotebookMigrationState(
      completed: json['completed'] == true,
      phase: json['phase'] as String? ?? 'copying',
      cursor: json['cursor'] is int ? json['cursor'] as int : 0,
      targetNotebookId: json['targetNotebookId'] as String?,
    );
  }
}

class NotebookStoreModel {
  final int version;
  final List<NotebookModel> notebooks;
  final NotebookMigrationState migration;

  const NotebookStoreModel({
    required this.version,
    required this.notebooks,
    required this.migration,
  });

  static const int currentVersion = 1;

  NotebookStoreModel copyWith({
    int? version,
    List<NotebookModel>? notebooks,
    NotebookMigrationState? migration,
  }) {
    return NotebookStoreModel(
      version: version ?? this.version,
      notebooks: notebooks ?? this.notebooks,
      migration: migration ?? this.migration,
    );
  }

  NotebookModel? findNotebook(String notebookId) {
    for (final notebook in notebooks) {
      if (notebook.id == notebookId) return notebook;
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'migration': migration.toJson(),
      'notebooks': notebooks.map((notebook) => notebook.toJson()).toList(),
    };
  }

  String toPrettyJson() {
    return const JsonEncoder.withIndent('  ').convert(toJson());
  }

  factory NotebookStoreModel.fromJson(Map<String, dynamic> json) {
    final rawNotebooks = json['notebooks'] as List<dynamic>? ?? const [];
    final migrationJson = json['migration'] as Map<String, dynamic>?;

    return NotebookStoreModel(
      version: json['version'] is int
          ? json['version'] as int
          : NotebookStoreModel.currentVersion,
      migration: migrationJson == null
          ? NotebookMigrationState.initial
          : NotebookMigrationState.fromJson(migrationJson),
      notebooks: rawNotebooks
          .whereType<Map<String, dynamic>>()
          .map(NotebookModel.fromJson)
          .toList(),
    );
  }
}
