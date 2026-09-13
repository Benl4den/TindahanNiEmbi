import 'package:flutter/material.dart';

import 'help_content.dart';
import 'help_guide_screen.dart';

class HelpButton extends StatelessWidget {
  const HelpButton({super.key, required this.topic});
  final HelpTopicId topic;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Help',
    icon: const Icon(Icons.help_outline),
    onPressed: () => showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final article = helpArticle(topic);
        return AlertDialog(
          icon: Icon(article.icon),
          title: Text(article.title),
          content: SizedBox(
            width: 420,
            child: Text(
              '${article.description}\n\n${article.steps.take(3).indexed.map((entry) => '${entry.$1 + 1}. ${entry.$2}').join('\n')}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HelpArticleScreen(article: article),
                  ),
                );
              },
              child: const Text('Open Full Guide'),
            ),
          ],
        );
      },
    ),
  );
}
