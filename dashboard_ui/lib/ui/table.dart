import 'package:flutter/material.dart';

import 'theme.dart';

// todo: try adding keys

// todo: support overview text (on the top left)

// todo: support additional actions (at the top right)

// todo: support copy csv to the clipboard

typedef OnTap<T> = void Function(T object);

class VTable<T> extends StatefulWidget {
  static const double _rowHeight = 42;
  static const double _vertPadding = 4;
  static const double _horizPadding = 8;

  final List<T> items;
  final List<VTableColumn<T>> columns;
  final bool startsSorted;
  final bool supportsSelection;
  final bool hideHeader;
  final OnTap<T>? onTap;

  const VTable({
    required this.items,
    required this.columns,
    this.startsSorted = false,
    this.supportsSelection = false,
    this.hideHeader = false,
    this.onTap,
    Key? key,
  }) : super(key: key);

  @override
  State<VTable> createState() => _VTableState<T>();
}

class _VTableState<T> extends State<VTable<T>> {
  late ScrollController scrollController;
  late List<T> sortedItems;
  int? sortColumnIndex;
  bool sortAscending = true;
  final ValueNotifier<T?> selectedItem = ValueNotifier(null);

  @override
  void initState() {
    super.initState();

    scrollController = ScrollController();
    sortedItems = widget.items.toList();

    if (widget.startsSorted && columns.first.supportsSort) {
      columns.first.sort(sortedItems, ascending: true);
      sortColumnIndex = 0;
    }
  }

  List<VTableColumn<T>> get columns => widget.columns;

  @override
  Widget build(BuildContext context) {
    final rowSeparator = BoxDecoration(
      border: Border(top: BorderSide(color: Colors.grey.shade300)),
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        Map<VTableColumn, double> colWidths = _layoutColumns(constraints);
        var sortColumn =
            sortColumnIndex == null ? null : columns[sortColumnIndex!];

        return Column(
          children: [
            if (!widget.hideHeader)
              Row(
                children: [
                  for (var column in columns)
                    InkWell(
                      onTap: () => trySort(column),
                      child: _ColumnHeader(
                        title: column.label,
                        width: colWidths[column],
                        alignment: column.alignment,
                        sortAscending:
                            column == sortColumn ? sortAscending : null,
                      ),
                    ),
                ],
              ),
            Expanded(
              child: ListView.builder(
                key: ObjectKey(widget.items),
                controller: scrollController,
                itemCount: sortedItems.length,
                itemExtent: VTable._rowHeight,
                itemBuilder: (BuildContext context, int index) {
                  T item = sortedItems[index];
                  final selected = item == selectedItem.value;
                  return Container(
                    color: selected ? Theme.of(context).hoverColor : null,
                    child: InkWell(
                      onTap: () => _select(item),
                      child: DecoratedBox(
                        decoration: rowSeparator,
                        child: Row(children: [
                          for (var column in columns)
                            Padding(
                              padding: const EdgeInsets.only(top: 1, right: 1),
                              child: SizedBox(
                                height: VTable._rowHeight - 1,
                                width: colWidths[column]! - 1,
                                child: Tooltip(
                                  message: column.validate(item)?.message ?? '',
                                  waitDuration: tooltipDelay,
                                  child: Container(
                                    alignment: column.alignment ??
                                        Alignment.centerLeft,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: VTable._horizPadding,
                                      vertical: VTable._vertPadding,
                                    ),
                                    color:
                                        column.validate(item)?.colorForSeverity,
                                    child: column.widgetFor(context, item),
                                  ),
                                ),
                              ),
                            )
                        ]),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  void trySort(VTableColumn<T> column) {
    if (!column.supportsSort) {
      return;
    }

    setState(() {
      int newIndex = columns.indexOf(column);
      if (sortColumnIndex == newIndex) {
        sortAscending = !sortAscending;
      } else {
        sortAscending = true;
      }

      sortColumnIndex = newIndex;
      column.sort(sortedItems, ascending: sortAscending);
    });
  }

  Map<VTableColumn, double> _layoutColumns(BoxConstraints constraints) {
    double width = constraints.maxWidth;

    Map<VTableColumn, double> widths = {};
    double minColWidth = 0;
    double totalGrow = 0;

    for (var col in columns) {
      minColWidth += col.width;
      totalGrow += col.grow;

      widths[col] = col.width.toDouble();
    }

    width -= minColWidth;

    if (width > 0 && totalGrow > 0) {
      for (var col in columns) {
        if (col.grow > 0) {
          var inc = width * (col.grow / totalGrow);
          widths[col] = widths[col]! + inc;
          // width -= inc;
        }
      }
    }

    return widths;
  }

  void _select(T item) {
    if (widget.supportsSelection) {
      setState(() {
        if (selectedItem.value != item) {
          selectedItem.value = item;
        } else {
          selectedItem.value = null;
        }
      });
    }

    if (widget.onTap != null) {
      widget.onTap!(item);
    }
  }
}

class _ColumnHeader extends StatelessWidget {
  final String title;
  final Alignment? alignment;
  final double? width;
  final bool? sortAscending;

  const _ColumnHeader({
    required this.title,
    required this.width,
    this.alignment,
    this.sortAscending,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var swapSortIconSized = alignment != null && alignment!.x > 0;

    return SizedBox(
      height: VTable._rowHeight,
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: VTable._horizPadding,
          vertical: VTable._vertPadding,
        ),
        //alignment: alignment ?? Alignment.centerLeft,
        child: Row(
          //mainAxisSize: MainAxisSize.min,
          children: [
            if (sortAscending != null && swapSortIconSized)
              AnimatedRotation(
                turns: sortAscending! ? 0 : 0.5,
                duration: const Duration(milliseconds: 200),
                child: const Icon(Icons.keyboard_arrow_up),
              ),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
                textAlign: swapSortIconSized ? TextAlign.end : null,
              ),
            ),
            if (sortAscending != null && !swapSortIconSized)
              AnimatedRotation(
                turns: sortAscending! ? 0 : 0.5,
                duration: const Duration(milliseconds: 200),
                child: const Icon(Icons.keyboard_arrow_up),
              ),
          ],
        ),
      ),
    );
  }
}

typedef RenderFunction<T> = Widget Function(BuildContext context, T object);
typedef TransformFunction<T> = String Function(T object);
typedef StyleFunction<T> = TextStyle? Function(T object);
typedef CompareFunction<T> = int Function(T a, T b);
typedef ValidationFunction<T> = ValidationResult? Function(T object);

class VTableColumn<T> {
  final String label;
  final int width;
  final double grow;
  final Alignment? alignment;

  final TransformFunction<T>? transformFunction;
  final StyleFunction<T>? styleFunction;
  final CompareFunction<T>? compareFunction;
  final List<ValidationFunction<T>> validators;
  final RenderFunction<T>? renderFunction;

  VTableColumn({
    required this.label,
    required this.width,
    this.alignment,
    this.grow = 0,
    this.transformFunction,
    this.styleFunction,
    this.compareFunction,
    this.validators = const [],
    this.renderFunction,
  });

  Widget widgetFor(BuildContext context, T item) {
    if (renderFunction != null) {
      return renderFunction!(context, item);
    }

    final str = transformFunction != null ? transformFunction!(item) : '$item';
    var style = styleFunction == null ? null : styleFunction!(item);
    return Text(
      str,
      style: style,
      maxLines: 2,
    );
  }

  void sort(List<T> items, {required bool ascending}) {
    if (compareFunction != null) {
      items
          .sort(ascending ? compareFunction : (a, b) => compareFunction!(b, a));
    } else if (transformFunction != null) {
      items.sort((T a, T b) {
        var strA = transformFunction!(a);
        var strB = transformFunction!(b);
        return ascending ? strA.compareTo(strB) : strB.compareTo(strA);
      });
    }
  }

  bool get supportsSort => compareFunction != null || transformFunction != null;

  ValidationResult? validate(T item) {
    if (validators.isEmpty) {
      return null;
    } else if (validators.length == 1) {
      return validators.first(item);
    } else {
      List<ValidationResult> results = [];
      for (var validator in validators) {
        ValidationResult? result = validator(item);
        if (result != null) {
          results.add(result);
        }
      }
      return ValidationResult.combine(results);
    }
  }
}

enum Severity {
  info,
  warning,
  error,
}

class ValidationResult {
  final String message;
  final Severity severity;

  ValidationResult(this.message, this.severity);

  factory ValidationResult.error(String message) =>
      ValidationResult(message, Severity.error);

  factory ValidationResult.warning(String message) =>
      ValidationResult(message, Severity.warning);

  IconData get icon {
    switch (severity) {
      case Severity.info:
        return Icons.info;
      case Severity.warning:
        return Icons.warning;
      case Severity.error:
        return Icons.error_rounded;
    }
  }

  Color get colorForSeverity {
    switch (severity) {
      case Severity.info:
        return Colors.grey.shade400.withAlpha(127);
      case Severity.warning:
        return Colors.yellow.shade200.withAlpha(127);
      case Severity.error:
        return Colors.red.shade300.withAlpha(127);
    }
  }

  @override
  String toString() => '$severity $message';

  static ValidationResult? combine(List<ValidationResult> results) {
    if (results.isEmpty) {
      return null;
    } else if (results.length == 1) {
      return results.first;
    } else {
      String message = results.map((r) => r.message).join('\n');
      Severity severity = results
          .map((r) => r.severity)
          .reduce((a, b) => a.index >= b.index ? a : b);
      return ValidationResult(message, severity);
    }
  }
}
