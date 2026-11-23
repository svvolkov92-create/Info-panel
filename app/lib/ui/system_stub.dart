import '../core/model.dart';
import 'desktop.dart';

class SystemIntegration {
  SystemIntegration(this.m, this.desk);
  final PanelModel m;
  final DesktopWindow? desk;
  void Function(String id)? onOpenTask;
  void Function()? onSettings;

  Future<void> init() async {}
  Future<void> notify(Notice n) async {}
  void dispose() {}
}
