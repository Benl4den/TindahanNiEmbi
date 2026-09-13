import 'package:flutter/material.dart';

import 'help_content.dart';

class HelpGuideScreen extends StatefulWidget {
  const HelpGuideScreen({super.key, this.initialTopic});
  final HelpTopicId? initialTopic;

  @override
  State<HelpGuideScreen> createState() => _HelpGuideScreenState();
}

class _HelpGuideScreenState extends State<HelpGuideScreen> {
  final query = TextEditingController();

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = helpArticles
        .where((article) => article.matches(query.text))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Help & Guide')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Simple guides for using your store app.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: query,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search help...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: query.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () => setState(query.clear),
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
          const SizedBox(height: 20),
          if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Center(
                child: Text(
                  'No guides found. Try another word or browse the topics below.',
                ),
              ),
            )
          else
            for (final group in helpGroups) ...[
              if (filtered.any((article) => article.group == group)) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: Text(
                    group,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                ...filtered
                    .where((article) => article.group == group)
                    .map(_tile),
              ],
            ],
        ],
      ),
    );
  }

  Widget _tile(HelpArticle article) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Icon(article.icon),
      title: Text(article.title),
      subtitle: Text(
        article.description,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => HelpArticleScreen(article: article)),
      ),
    ),
  );
}

class HelpArticleScreen extends StatelessWidget {
  const HelpArticleScreen({super.key, required this.article});
  final HelpArticle article;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(article.title)),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(
          article.icon,
          size: 42,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(article.title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(article.description, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 24),
        Text('How to use it', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        ...article.steps.indexed.map(
          (entry) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(radius: 14, child: Text('${entry.$1 + 1}')),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      entry.$2,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (article.notes.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Helpful notes', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...article.notes.map(
            (note) => Card(
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(note),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}
