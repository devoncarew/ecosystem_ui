import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart' as url;

import '../utils/constants.dart';

class OverlayButtons extends StatelessWidget {
  final String? infoText;
  final List<Widget> children;

  const OverlayButtons({
    this.infoText,
    required this.children,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            const Expanded(child: SizedBox()),
            if (infoText != null)
              Opacity(
                opacity: 0.5,
                child: Chip(label: Text(infoText!)),
              ),
            ...children,
          ],
        ),
        const Expanded(child: SizedBox()),
      ],
    );
  }
}

class Hyperlink extends StatefulWidget {
  final String url;
  final String? displayText;
  final TextStyle? style;

  const Hyperlink({
    required this.url,
    this.displayText,
    this.style,
    Key? key,
  }) : super(key: key);

  @override
  State<Hyperlink> createState() => _HyperlinkState();
}

class _HyperlinkState extends State<Hyperlink> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    const underline = TextStyle(decoration: TextDecoration.underline);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (event) {
        setState(() => hovered = true);
      },
      onExit: (event) {
        setState(() => hovered = false);
      },
      child: GestureDetector(
        onTap: () => url.launchUrl(Uri.parse(widget.url)),
        child: Text(
          widget.displayText ?? widget.url,
          style: hovered ? underline.merge(widget.style) : widget.style,
        ),
      ),
    );
  }
}

class SearchField extends StatelessWidget {
  const SearchField({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 125,
      height: 36,
      child: TextField(
        cursorColor: Colors.grey,
        decoration: InputDecoration(
          fillColor: Colors.white,
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          hintText: 'Search',
          hintStyle: const TextStyle(color: Colors.grey, fontSize: 18),
          prefixIcon: const Icon(Icons.search),
        ),
      ),
    );
  }
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(appName),
      ),
      body: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class LargeDialog extends StatelessWidget {
  final String title;
  final Widget child;

  const LargeDialog({
    required this.title,
    required this.child,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      var width = constraints.maxWidth - 48 * 2;
      var height = constraints.maxHeight - 48 * 2;

      return AlertDialog(
        title: Text(title),
        contentTextStyle: Theme.of(context).textTheme.bodyText2,
        contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
        content: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.grey)),
          ),
          child: SizedBox(
            width: width,
            height: height,
            child: ClipRect(child: child),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    });
  }
}

abstract class NavPage {
  final String title;

  NavPage(this.title);

  int? get tabPages => null;

  PreferredSizeWidget? createBottomBar(BuildContext context) => null;

  Widget createChild(BuildContext context, {Key? key});
}

class TempPage extends NavPage {
  TempPage(String name) : super('Temp page $name');

  @override
  Widget createChild(BuildContext context, {Key? key}) {
    return Center(
      key: key,
      child: Text(title),
    );
  }
}

const _toolbarHeight = 32.0;

class ExclusiveToggleButtons<T extends Enum> extends StatelessWidget {
  final List<T> values;
  final T selection;
  final void Function(T item)? onPressed;

  const ExclusiveToggleButtons({
    required this.values,
    required this.selection,
    this.onPressed,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _toolbarHeight),
      child: ToggleButtons(
        borderRadius: BorderRadius.circular(6),
        textStyle: Theme.of(context).textTheme.subtitle1,
        isSelected: [
          ...values.map((e) => e == selection),
        ],
        onPressed: (index) {
          if (onPressed != null) {
            onPressed!(values[index]);
          }
        },
        children: [
          ...values.map((e) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(_splitCamelCase(e.name)),
            );
          }),
        ],
      ),
    );
  }

  static String _splitCamelCase(String str) {
    return str.characters
        .map((c) => c == c.toLowerCase() ? c : ' ${c.toLowerCase()}')
        .join();
  }
}
