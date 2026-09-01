import 'package:sqflite/sqflite.dart';

import '../database_migration.dart';

class MigrationV1 implements DatabaseMigration {
  @override
  int get version => 1;

  @override
  Future<void> migrate(DatabaseExecutor db) async {
    for (final statement in _statements) {
      await db.execute(statement);
    }
    await db.insert('schema_migrations', {
      'version': version,
      'applied_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static const _statements = <String>[
    '''
      CREATE TABLE schema_migrations (
        version INTEGER PRIMARY KEY,
        applied_at TEXT NOT NULL
      )
    ''',
    '''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL COLLATE NOCASE UNIQUE,
        is_archived INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0, 1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''',
    '''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY,
        category_id INTEGER REFERENCES categories(id) ON DELETE RESTRICT,
        name TEXT NOT NULL CHECK (length(trim(name)) > 0),
        photo_path TEXT,
        purchase_price_centavos INTEGER NOT NULL DEFAULT 0 CHECK (purchase_price_centavos >= 0),
        selling_price_centavos INTEGER NOT NULL DEFAULT 0 CHECK (selling_price_centavos >= 0),
        current_quantity INTEGER NOT NULL DEFAULT 0 CHECK (current_quantity >= 0),
        minimum_stock_level INTEGER NOT NULL DEFAULT 0 CHECK (minimum_stock_level >= 0),
        is_archived INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0, 1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''',
    '''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY,
        full_name TEXT NOT NULL CHECK (length(trim(full_name)) > 0),
        nickname TEXT,
        mobile_number TEXT,
        address TEXT,
        notes TEXT,
        is_archived INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0, 1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''',
    '''
      CREATE TABLE inventory_transactions (
        id INTEGER PRIMARY KEY,
        type TEXT NOT NULL CHECK (type IN (
          'INITIAL_STOCK', 'STOCK_IN', 'CASH_SALE', 'UTANG',
          'ADJUSTMENT_IN', 'ADJUSTMENT_OUT', 'RETURN', 'REVERSAL'
        )),
        reference_number TEXT,
        notes TEXT,
        occurred_at TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''',
    '''
      CREATE TABLE utang_transactions (
        id INTEGER PRIMARY KEY,
        customer_id INTEGER NOT NULL REFERENCES customers(id) ON DELETE RESTRICT,
        total_centavos INTEGER NOT NULL CHECK (total_centavos > 0),
        status TEXT NOT NULL DEFAULT 'POSTED' CHECK (status IN ('POSTED', 'VOIDED', 'REVERSED')),
        notes TEXT,
        occurred_at TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''',
    '''
      CREATE TABLE utang_transaction_items (
        id INTEGER PRIMARY KEY,
        utang_transaction_id INTEGER NOT NULL REFERENCES utang_transactions(id) ON DELETE RESTRICT,
        product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
        product_name_snapshot TEXT NOT NULL CHECK (length(trim(product_name_snapshot)) > 0),
        unit_price_centavos INTEGER NOT NULL CHECK (unit_price_centavos >= 0),
        quantity INTEGER NOT NULL CHECK (quantity > 0),
        line_total_centavos INTEGER NOT NULL CHECK (
          line_total_centavos >= 0 AND
          line_total_centavos = unit_price_centavos * quantity
        ),
        created_at TEXT NOT NULL
      )
    ''',
    '''
      CREATE TABLE inventory_movements (
        id INTEGER PRIMARY KEY,
        inventory_transaction_id INTEGER NOT NULL REFERENCES inventory_transactions(id) ON DELETE RESTRICT,
        product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
        quantity_change INTEGER NOT NULL CHECK (quantity_change <> 0),
        quantity_before INTEGER NOT NULL CHECK (quantity_before >= 0),
        quantity_after INTEGER NOT NULL CHECK (quantity_after >= 0),
        unit_cost_centavos INTEGER CHECK (unit_cost_centavos >= 0),
        utang_item_id INTEGER UNIQUE REFERENCES utang_transaction_items(id) ON DELETE RESTRICT,
        created_at TEXT NOT NULL,
        CHECK (quantity_after = quantity_before + quantity_change)
      )
    ''',
    '''
      CREATE TABLE utang_payments (
        id INTEGER PRIMARY KEY,
        customer_id INTEGER NOT NULL REFERENCES customers(id) ON DELETE RESTRICT,
        amount_centavos INTEGER NOT NULL CHECK (amount_centavos > 0),
        status TEXT NOT NULL DEFAULT 'POSTED' CHECK (status IN ('POSTED', 'VOIDED', 'REVERSED')),
        notes TEXT,
        paid_at TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''',
    '''
      CREATE TABLE customer_ledger_entries (
        id INTEGER PRIMARY KEY,
        customer_id INTEGER NOT NULL REFERENCES customers(id) ON DELETE RESTRICT,
        entry_type TEXT NOT NULL CHECK (entry_type IN (
          'UTANG', 'PAYMENT', 'UTANG_REVERSAL', 'PAYMENT_REVERSAL'
        )),
        amount_change_centavos INTEGER NOT NULL CHECK (amount_change_centavos <> 0),
        utang_transaction_id INTEGER REFERENCES utang_transactions(id) ON DELETE RESTRICT,
        payment_id INTEGER REFERENCES utang_payments(id) ON DELETE RESTRICT,
        description TEXT,
        occurred_at TEXT NOT NULL,
        created_at TEXT NOT NULL,
        CHECK (
          (entry_type IN ('UTANG', 'PAYMENT_REVERSAL') AND amount_change_centavos > 0) OR
          (entry_type IN ('PAYMENT', 'UTANG_REVERSAL') AND amount_change_centavos < 0)
        ),
        CHECK (
          (entry_type IN ('UTANG', 'UTANG_REVERSAL') AND utang_transaction_id IS NOT NULL AND payment_id IS NULL) OR
          (entry_type IN ('PAYMENT', 'PAYMENT_REVERSAL') AND payment_id IS NOT NULL AND utang_transaction_id IS NULL)
        )
      )
    ''',
    'CREATE INDEX idx_products_name ON products(name COLLATE NOCASE)',
    'CREATE INDEX idx_products_category ON products(category_id)',
    'CREATE INDEX idx_products_active_stock ON products(is_archived, current_quantity)',
    'CREATE INDEX idx_inventory_movements_product_date ON inventory_movements(product_id, created_at)',
    'CREATE INDEX idx_inventory_transactions_type_date ON inventory_transactions(type, occurred_at)',
    'CREATE INDEX idx_customers_name ON customers(full_name COLLATE NOCASE)',
    'CREATE INDEX idx_customers_nickname ON customers(nickname COLLATE NOCASE)',
    'CREATE INDEX idx_utang_customer_date ON utang_transactions(customer_id, occurred_at)',
    'CREATE INDEX idx_payments_customer_date ON utang_payments(customer_id, paid_at)',
    'CREATE INDEX idx_ledger_customer_date ON customer_ledger_entries(customer_id, occurred_at, id)',
    "CREATE UNIQUE INDEX idx_ledger_utang_once ON customer_ledger_entries(utang_transaction_id) WHERE entry_type = 'UTANG'",
    "CREATE UNIQUE INDEX idx_ledger_utang_reversal_once ON customer_ledger_entries(utang_transaction_id) WHERE entry_type = 'UTANG_REVERSAL'",
    "CREATE UNIQUE INDEX idx_ledger_payment_once ON customer_ledger_entries(payment_id) WHERE entry_type = 'PAYMENT'",
    "CREATE UNIQUE INDEX idx_ledger_payment_reversal_once ON customer_ledger_entries(payment_id) WHERE entry_type = 'PAYMENT_REVERSAL'",
    '''
      CREATE TRIGGER products_initial_quantity_must_be_zero
      BEFORE INSERT ON products
      WHEN NEW.current_quantity <> 0
      BEGIN
        SELECT RAISE(ABORT, 'INITIAL_QUANTITY_REQUIRES_MOVEMENT');
      END
    ''',
    '''
      CREATE TRIGGER products_quantity_matches_ledger
      BEFORE UPDATE OF current_quantity ON products
      WHEN NEW.current_quantity <> COALESCE((
        SELECT SUM(quantity_change) FROM inventory_movements WHERE product_id = OLD.id
      ), 0)
      BEGIN
        SELECT RAISE(ABORT, 'QUANTITY_MUST_MATCH_INVENTORY_LEDGER');
      END
    ''',
    '''
      CREATE TRIGGER inventory_movement_validate_before_insert
      BEFORE INSERT ON inventory_movements
      BEGIN
        SELECT CASE
          WHEN (SELECT id FROM products WHERE id = NEW.product_id) IS NULL
            THEN RAISE(ABORT, 'PRODUCT_NOT_FOUND')
          WHEN NEW.quantity_before <> (SELECT current_quantity FROM products WHERE id = NEW.product_id)
            THEN RAISE(ABORT, 'STALE_PRODUCT_QUANTITY')
          WHEN NEW.quantity_after < 0
            THEN RAISE(ABORT, 'INSUFFICIENT_STOCK')
        END;
      END
    ''',
    '''
      CREATE TRIGGER inventory_movement_update_product
      AFTER INSERT ON inventory_movements
      BEGIN
        UPDATE products
        SET current_quantity = NEW.quantity_after, updated_at = NEW.created_at
        WHERE id = NEW.product_id;
      END
    ''',
    '''
      CREATE TRIGGER inventory_movements_no_update
      BEFORE UPDATE ON inventory_movements
      BEGIN
        SELECT RAISE(ABORT, 'INVENTORY_MOVEMENTS_ARE_APPEND_ONLY');
      END
    ''',
    '''
      CREATE TRIGGER inventory_movements_no_delete
      BEFORE DELETE ON inventory_movements
      BEGIN
        SELECT RAISE(ABORT, 'INVENTORY_MOVEMENTS_ARE_APPEND_ONLY');
      END
    ''',
    '''
      CREATE TRIGGER customer_ledger_prevent_negative_balance
      BEFORE INSERT ON customer_ledger_entries
      WHEN COALESCE((
        SELECT SUM(amount_change_centavos)
        FROM customer_ledger_entries
        WHERE customer_id = NEW.customer_id
      ), 0) + NEW.amount_change_centavos < 0
      BEGIN
        SELECT RAISE(ABORT, 'PAYMENT_EXCEEDS_BALANCE');
      END
    ''',
    '''
      CREATE TRIGGER customer_ledger_no_update
      BEFORE UPDATE ON customer_ledger_entries
      BEGIN
        SELECT RAISE(ABORT, 'CUSTOMER_LEDGER_IS_APPEND_ONLY');
      END
    ''',
    '''
      CREATE TRIGGER customer_ledger_no_delete
      BEFORE DELETE ON customer_ledger_entries
      BEGIN
        SELECT RAISE(ABORT, 'CUSTOMER_LEDGER_IS_APPEND_ONLY');
      END
    ''',
  ];
}
