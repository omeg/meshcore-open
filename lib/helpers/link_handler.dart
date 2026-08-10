import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/l10n.dart';
import '../models/meshcore_share_link.dart';
import '../screens/share_link_screen.dart';
import '../utils/platform_info.dart';
import '../helpers/snack_bar_builder.dart';

class MeshCoreLinkifier extends Linkifier {
  const MeshCoreLinkifier();

  @override
  List<LinkifyElement> parse(
    List<LinkifyElement> elements,
    LinkifyOptions options,
  ) {
    final result = <LinkifyElement>[];
    for (final element in elements) {
      if (element is! TextElement) {
        result.add(element);
        continue;
      }

      var offset = 0;
      for (final match in MeshCoreShareLink.findInText(element.text)) {
        if (match.start > offset) {
          result.add(TextElement(element.text.substring(offset, match.start)));
        }
        result.add(LinkableElement(match.text, match.text));
        offset = match.end;
      }
      if (offset < element.text.length) {
        result.add(TextElement(element.text.substring(offset)));
      }
    }
    return result;
  }
}

class LinkHandler {
  static TextStyle defaultLinkStyle(BuildContext context, TextStyle base) {
    final brightness = Theme.of(context).brightness;
    final orange = brightness == Brightness.dark
        ? const Color(0xFFFFB74D)
        : const Color(0xFFE65100);
    return base.copyWith(color: orange, decoration: TextDecoration.underline);
  }

  /// Returns a [SelectableLinkify] on desktop or a [Linkify] on mobile.
  static Widget buildLinkifyText({
    required BuildContext context,
    required String text,
    required TextStyle style,
    TextStyle? linkStyle,
    VoidCallback? onSecondaryTap,
  }) {
    final effectiveLinkStyle = linkStyle ?? defaultLinkStyle(context, style);
    const options = LinkifyOptions(humanize: false, defaultToHttps: false);
    const linkifiers = [MeshCoreLinkifier(), UrlLinkifier(), EmailLinkifier()];
    void onOpen(LinkableElement link) => handleLinkTap(context, link.url);

    if (PlatformInfo.isDesktop) {
      final linkify = SelectableLinkify(
        text: text,
        style: style,
        linkStyle: effectiveLinkStyle,
        options: options,
        linkifiers: linkifiers,
        onOpen: onOpen,
      );
      if (onSecondaryTap == null) return linkify;
      return Listener(
        onPointerDown: (event) {
          if (event.buttons & kSecondaryMouseButton != 0) onSecondaryTap();
        },
        behavior: HitTestBehavior.translucent,
        child: linkify,
      );
    }
    return Linkify(
      text: text,
      style: style,
      linkStyle: effectiveLinkStyle,
      options: options,
      linkifiers: linkifiers,
      onOpen: onOpen,
    );
  }

  static Future<void> handleLinkTap(BuildContext context, String url) async {
    final shareLink = MeshCoreShareLink.tryParse(url);
    if (shareLink != null) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (context) => ShareLinkScreen(link: shareLink),
        ),
      );
      return;
    }

    // Show confirmation dialog
    final shouldOpen = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.chat_openLink),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.chat_openLinkConfirmation,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                url,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.chat_open),
          ),
        ],
      ),
    );

    if (shouldOpen != true) return;

    // Launch URL
    try {
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (context.mounted) {
          showDismissibleSnackBar(
            context,
            content: Text(context.l10n.chat_couldNotOpenLink(url)),
            backgroundColor: Colors.red,
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        showDismissibleSnackBar(
          context,
          content: Text(context.l10n.chat_invalidLink),
          backgroundColor: Colors.red,
        );
      }
    }
  }
}
