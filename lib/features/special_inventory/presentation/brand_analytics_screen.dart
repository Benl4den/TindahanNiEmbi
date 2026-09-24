import 'package:flutter/material.dart';

import '../../../core/formatters/number_format.dart';
import '../../../repositories/brand_analytics_repository.dart';
import '../../../services/feature_access_service.dart';
import '../../../widgets/pro_feature_preview.dart';
import '../../../widgets/feature_access_builder.dart';

class BrandAnalyticsScreen extends StatelessWidget {
  const BrandAnalyticsScreen({
    super.key,
    required this.groupCode,
    required this.groupName,
    required this.analytics,
    required this.access,
  });
  final String groupCode, groupName;
  final BrandAnalyticsRepository analytics;
  final FeatureAccessService access;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('$groupName Analytics')),
    body: FeatureAccessBuilder(
      access: access,
      feature: ProFeature.managedBrandAnalytics,
      builder: (_, allowed) {
        if (!allowed) {
          return const ProFeaturePreview(
            title: 'Brand performance analytics',
            description: 'See sales, estimated profit, stock health, and the products that move your brand.',
            icon: Icons.insights_outlined,
          );
        }
        return FutureBuilder<Map<String, Object?>>(
          future: analytics.summary(groupCode),
          builder: (_, summary) {
            if (summary.hasError) {
              return const Center(
                child: Text(
                  'Could not load brand analytics. Reopen this section.',
                ),
              );
            }
            if (!summary.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final d = summary.data!;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'How $groupName is performing',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _Metric(
                      'Sales',
                      standardMoney(d['sales']! as int),
                      Icons.payments_outlined,
                    ),
                    _Metric(
                      'Estimated cost',
                      standardMoney(d['cost']! as int),
                      Icons.inventory_2_outlined,
                    ),
                    _Metric(
                      'Estimated profit',
                      standardMoney(d['profit']! as int),
                      Icons.trending_up,
                    ),
                    _Metric(
                      'Units sold',
                      '${d['units']}',
                      Icons.shopping_bag_outlined,
                    ),
                  ],
                ),
                if ((d['estimatedItems'] as int? ?? 0) > 0)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Cost and profit are estimates based on the recorded product cost when sold. Older sales use the cost available when this feature was added.',
                    ),
                  ),
                const SizedBox(height: 24),
                Text('Products', style: Theme.of(context).textTheme.titleLarge),
                FutureBuilder<List<Map<String, Object?>>>(
                  future: analytics.products(groupCode),
                  builder: (_, products) {
                    if (products.hasError) {
                      return const Text('Could not load brand products.');
                    }
                    if (!products.hasData) {
                      return const Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(),
                      );
                    }
                    return Column(
                      children: products.data!
                          .map(
                            (x) => Card(
                              child: ListTile(
                                title: Text(x['name']! as String),
                                subtitle: Text(
                                  '${x['current_quantity']} in stock • ${x['stock_status']}',
                                ),
                                trailing: Text(
                                  standardMoney(
                                    x['selling_price_centavos']! as int,
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.icon);
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext c) => SizedBox(
    width: 220,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(height: 10),
            Text(label),
            Text(value, style: Theme.of(c).textTheme.titleLarge),
          ],
        ),
      ),
    ),
  );
}
