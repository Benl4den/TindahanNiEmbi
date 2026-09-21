import 'package:flutter/material.dart';

class ProFeaturePreview extends StatelessWidget {
  const ProFeaturePreview({
    super.key,
    required this.title,
    required this.description,
    this.icon = Icons.workspace_premium_outlined,
  });
  final String title, description;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(radius: 34, child: Icon(icon, size: 36)),
              const SizedBox(height: 18),
              const Chip(
                avatar: Icon(Icons.workspace_premium, size: 18),
                label: Text('PRO FEATURE'),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                description,
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Text(
                'Your existing store records stay safely on this device. Subscription options will appear here when available.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
