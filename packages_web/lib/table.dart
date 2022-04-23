// ignore_for_file: avoid_print

import 'package:flutter/material.dart';

// todo: try adding keys

class PicnicTable<T> extends StatefulWidget {
  static const double _rowHeight = 42;
  static const double _vertPadding = 4;
  static const double _horizPadding = 8;

  final List<T> items;
  final List<PicnicColumn<T>> columns;

  const PicnicTable({
    required this.items,
    required this.columns,
    Key? key,
  }) : super(key: key);

  @override
  State<PicnicTable> createState() => _PicnicTableState<T>();
}

class _PicnicTableState<T> extends State<PicnicTable<T>> {
  late ScrollController scrollController;
  late List<T> sortedItems;
  int? sortColumnIndex;
  bool sortAscending = true;

  @override
  void initState() {
    super.initState();

    scrollController = ScrollController();
    sortedItems = widget.items.toList();
    if (columns.first.supportsSort) {
      columns.first.sort(sortedItems, ascending: true);
      sortColumnIndex = 0;
    }
  }

  List<PicnicColumn<T>> get columns => widget.columns;

  @override
  Widget build(BuildContext context) {
    final rowSeparator = BoxDecoration(
      border: Border(top: BorderSide(color: Colors.grey.shade300)),
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        Map<PicnicColumn, double> colWidths = _layoutColumns(constraints);
        var sortColumn =
            sortColumnIndex == null ? null : columns[sortColumnIndex!];

        return Column(
          children: [
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
                itemExtent: PicnicTable._rowHeight,
                itemBuilder: (BuildContext context, int index) {
                  return InkWell(
                    onTap: () {
                      print('ontap: row $index');
                    },
                    child: DecoratedBox(
                      decoration: rowSeparator,
                      child: Row(children: [
                        for (var column in columns)
                          SizedBox(
                            height: PicnicTable._rowHeight - 1,
                            width: colWidths[column],
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: PicnicTable._horizPadding,
                                vertical: PicnicTable._vertPadding,
                              ),
                              child: Align(
                                alignment:
                                    column.alignment ?? Alignment.centerLeft,
                                child: column.widgetFor(
                                  context,
                                  sortedItems[index],
                                ),
                              ),
                            ),
                          )
                      ]),
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

  void trySort(PicnicColumn<T> column) {
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

  Map<PicnicColumn, double> _layoutColumns(BoxConstraints constraints) {
    double width = constraints.maxWidth;

    Map<PicnicColumn, double> widths = {};
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
      height: PicnicTable._rowHeight,
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: PicnicTable._horizPadding,
          vertical: PicnicTable._vertPadding,
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

//typedef RenderFunction<T> = Widget Function(BuildContext context, T object);
typedef TransformFunction<T> = String Function(T object);
typedef StyleFunction<T> = TextStyle? Function(T object);
typedef CompareFunction<T> = int Function(T a, T b);

class PicnicColumn<T> {
  final String label;
  final int width;
  final double grow;
  final Alignment? alignment;

  final TransformFunction<T>? transformFunction;
  final StyleFunction<T>? styleFunction;
  final CompareFunction<T>? compareFunction;
  //final RenderFunction<T>? renderFunction;

  PicnicColumn({
    required this.label,
    required this.width,
    this.alignment,
    this.grow = 0,
    this.transformFunction,
    this.styleFunction,
    this.compareFunction,
    //this.renderFunction,
  });

  Widget widgetFor(BuildContext context, T item) {
    // if (renderFunction != null) {
    //   return renderFunction!(context, item);
    // }

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
}
