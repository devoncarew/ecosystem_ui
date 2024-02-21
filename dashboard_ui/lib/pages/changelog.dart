import 'package:flutter/material.dart';
import 'package:vtable/vtable.dart';

import '../model/data_model.dart';

class ChangelogView extends StatelessWidget {
  final DataModel dataModel;

  const ChangelogView({
    required this.dataModel,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<LogItem>>(
      valueListenable: dataModel.changeLogItems,
      builder: (context, items, _) {
        return VTable<LogItem>(
          items: items,
          includeCopyToClipboardAction: true,
          columns: [
            VTableColumn(
              label: 'Entity',
              width: 150,
              grow: 0.2,
              transformFunction: (item) => item.entity,
            ),
            VTableColumn(
              label: 'Change',
              width: 250,
              grow: 0.4,
              transformFunction: (item) => item.change,
            ),
            VTableColumn(
              label: 'Timestamp',
              width: 150,
              grow: 0.1,
              transformFunction: (item) {
                return item.timestamp
                    .toDate()
                    .toIso8601String()
                    .replaceAll('T', ' ');
              },
              compareFunction: (a, b) {
                return a.timestamp.compareTo(b.timestamp);
              },
            ),
          ],
        );
      },
    );
  }
}
