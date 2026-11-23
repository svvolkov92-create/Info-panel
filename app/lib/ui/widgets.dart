import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/core.dart';
import 'theme.dart';

/// Текстовая кнопка панели: цветная надпись, подсветка при наведении.
class Btn extends StatelessWidget {
  const Btn(this.label, this.onTap, {super.key, this.color = C.accent, this.size = 12, this.bold = false, this.pad = 6});
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final double size;
  final bool bold;
  final double pad;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      hoverColor: C.hover,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 2),
        child: Text(label,
            style: TextStyle(color: onTap == null ? C.faint : color, fontSize: size, fontWeight: bold ? FontWeight.w600 : null)),
      ),
    );
  }
}

class IconBtn extends StatelessWidget {
  const IconBtn(this.icon, this.tip, this.onTap, {super.key, this.color = C.muted, this.size = 16});
  final IconData icon;
  final String tip;
  final VoidCallback? onTap;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        hoverColor: C.hover,
        child: Padding(padding: const EdgeInsets.all(3), child: Icon(icon, size: size, color: color)),
      ),
    );
  }
}

/// Переключатель-«фишка», как chip() в карточке задачи Python-версии.
class Pill extends StatelessWidget {
  const Pill(this.label, this.selected, this.onTap, {super.key, this.color = C.accent});
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4, bottom: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: selected ? mix(C.card, color, 0.45) : C.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? color : C.faint.withValues(alpha: 0.6)),
          ),
          child: Text(label, style: TextStyle(fontSize: 12, color: selected ? C.fg : C.muted)),
        ),
      ),
    );
  }
}

/// Однострочное поле: Enter — отправить, Ctrl+V со списком — каждая строка отдельно.
class Field extends StatefulWidget {
  const Field({
    super.key,
    required this.hint,
    required this.onSubmit,
    this.onPasteLines,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.onChanged,
    this.suffix,
    this.style,
    this.clearOnSubmit = true,
    this.onEscape,
  });

  final String hint;
  final void Function(String) onSubmit;
  final void Function(List<String>)? onPasteLines;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final void Function(String)? onChanged;
  final Widget? suffix;
  final TextStyle? style;
  final bool clearOnSubmit;
  final VoidCallback? onEscape;

  @override
  State<Field> createState() => _FieldState();
}

class _FieldState extends State<Field> {
  late final TextEditingController ctl = widget.controller ?? TextEditingController();

  @override
  void dispose() {
    if (widget.controller == null) ctl.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    final lines = pastedLines(text);
    if (widget.onPasteLines != null && lines.length > 1) {
      widget.onPasteLines!(lines);
      return;
    }
    final one = text.replaceAll(RegExp(r'[\r\n]+'), ' ');
    final v = ctl.value;
    final sel = v.selection.isValid ? v.selection : TextSelection.collapsed(offset: v.text.length);
    final nt = v.text.replaceRange(sel.start, sel.end, one);
    ctl.value = TextEditingValue(text: nt, selection: TextSelection.collapsed(offset: sel.start + one.length));
    widget.onChanged?.call(nt);
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): _paste,
        const SingleActivator(LogicalKeyboardKey.insert, shift: true): _paste,
        if (widget.onEscape != null) const SingleActivator(LogicalKeyboardKey.escape): widget.onEscape!,
      },
      child: TextField(
        controller: ctl,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        style: widget.style ?? T.norm,
        onChanged: widget.onChanged,
        // фокус остаётся в поле: задачи можно вводить подряд, нажимая Enter
        onEditingComplete: () {},
        onSubmitted: (v) {
          widget.onSubmit(v);
          if (widget.clearOnSubmit) {
            ctl.clear();
            widget.onChanged?.call('');
          }
        },
        decoration: InputDecoration(hintText: widget.hint, suffixIcon: widget.suffix,
            suffixIconConstraints: const BoxConstraints(minWidth: 24, minHeight: 24)),
      ),
    );
  }
}

/// Окно с полями ввода. ok возвращает текст ошибки или null — тогда окно закрывается.
Future<void> inputDialog(BuildContext context, String title, String hint, List<(String, String)> fields,
    String? Function(List<String>) ok, {String okText = 'Применить'}) {
  final ctls = [for (final f in fields) TextEditingController(text: f.$2)];
  String? error;
  return showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
      void submit() {
        final e = ok([for (final c in ctls) c.text.trim()]);
        if (e == null) {
          Navigator.pop(ctx);
        } else {
          setSt(() => error = e);
        }
      }

      return AlertDialog(
        backgroundColor: C.bg,
        title: Text(title, style: T.title.copyWith(fontSize: 15)),
        content: SizedBox(
          width: 340,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(hint, style: T.small.copyWith(color: C.muted)),
            const SizedBox(height: 10),
            for (var i = 0; i < fields.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  if (fields.length > 1) SizedBox(width: 150, child: Text(fields[i].$1, style: T.small)),
                  Expanded(
                    child: TextField(
                      controller: ctls[i],
                      autofocus: i == 0,
                      style: T.norm,
                      onSubmitted: (_) => submit(),
                      decoration: InputDecoration(hintText: fields.length == 1 ? fields[i].$1 : null),
                    ),
                  ),
                ]),
              ),
            if (error != null) Text(error!, style: T.small.copyWith(color: C.danger)),
          ]),
        ),
        actions: [
          Btn('Отмена', () => Navigator.pop(ctx), color: C.muted, size: 13),
          Btn(okText, submit, size: 13, bold: true),
        ],
      );
    }),
  );
}

/// Подтверждение действия; возвращает true, если согласились.
Future<bool> confirmDialog(BuildContext context, String title, String text, {String yes = 'Да'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: C.bg,
      title: Text(title, style: T.title.copyWith(fontSize: 15)),
      content: Text(text, style: T.small),
      actions: [
        Btn('Отмена', () => Navigator.pop(ctx, false), color: C.muted, size: 13),
        Btn(yes, () => Navigator.pop(ctx, true), size: 13, bold: true),
      ],
    ),
  );
  return r == true;
}

/// Заголовок раздела в окнах.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(top: 12, bottom: 4), child: Text(text, style: T.tiny));
}
