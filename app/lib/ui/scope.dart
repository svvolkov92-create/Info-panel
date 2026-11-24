import 'package:flutter/material.dart';

import '../core/model.dart';

/// Доступ к модели и общим действиям интерфейса из любого виджета панели.
class Scope extends InheritedWidget {
  const Scope({super.key, required this.m, required this.actions, required super.child});

  final PanelModel m;
  final PanelActions actions;

  static Scope of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<Scope>()!;

  /// Scope создаётся заново при каждом изменении модели (PanelApp слушает модель),
  /// поэтому все блоки перерисовываются: данные меняются внутри тех же объектов.
  @override
  bool updateShouldNotify(Scope old) => true;
}

/// Окна и диалоги, которые открываются из разных блоков.
abstract class PanelActions {
  void openCard(BuildContext context, String id);
  void openWeek(BuildContext context, {DateTime? start});
  void openMatrix(BuildContext context);
  void openGtd(BuildContext context, String view);
  void openSearch(BuildContext context);
  void openSettings(BuildContext context);
  void openWeeklyReview(BuildContext context);
  void openUnload(BuildContext context);
  void openMorningReview(BuildContext context);
  void openTarget(String target);
  Future<void> askDate(BuildContext context, String id);
  Future<void> askTime(BuildContext context, String id);
  Future<void> askDeadline(BuildContext context, String id);
  Future<void> askEst(BuildContext context, String id);
  Future<void> askRepeat(BuildContext context, String id);
  Future<void> askTemplateName(BuildContext context, List<Map<String, dynamic>> items, String name);
}

/// Задача, которую тащат мышью.
class DragTask {
  const DragTask(this.id);
  final String id;
}
