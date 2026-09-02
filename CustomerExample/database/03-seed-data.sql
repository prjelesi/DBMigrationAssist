WHENEVER SQLERROR EXIT SQL.SQLCODE
SET DEFINE OFF
SET SERVEROUTPUT ON

PROMPT Loading deterministic fictional Banana Commerce data...

INSERT INTO banana_customers (
    customer_id, customer_number, customer_type, legal_name, email,
    phone_number, tax_identifier, credit_limit, profile_json
) VALUES (
    NULL, 'B2B-NORD-001', 'BUSINESS', 'Nordic Fresh Markets AB',
    'orders@nordic-fresh.example', '+46-555-0101', 'SE-FICTION-001', 250000,
    '{"segment":"strategic","preferredLanguage":"sv","fictional":true}'
);

INSERT INTO banana_customers (
    customer_id, customer_number, customer_type, legal_name, email,
    phone_number, tax_identifier, credit_limit, profile_json
) VALUES (
    NULL, 'B2B-BALT-002', 'BUSINESS', 'Baltic Bistro Group OY',
    'purchasing@baltic-bistro.example', '+358-555-0102', 'FI-FICTION-002', 125000,
    '{"segment":"hospitality","preferredLanguage":"fi","fictional":true}'
);

INSERT INTO banana_customers (
    customer_id, customer_number, customer_type, legal_name, email,
    phone_number, credit_limit, profile_json
) VALUES (
    NULL, 'B2C-SE-003', 'CONSUMER', 'Fictional Customer Three',
    'customer.three@example.invalid', '+46-555-0103', 0,
    '{"segment":"consumer","marketingConsent":false,"fictional":true}'
);

INSERT INTO banana_customers (
    customer_id, customer_number, customer_type, legal_name, email,
    phone_number, tax_identifier, credit_limit, profile_json
) VALUES (
    NULL, 'B2B-DK-004', 'BUSINESS', 'Copenhagen Corner Stores AS',
    'supply@corner-stores.example', '+45-555-0104', 'DK-FICTION-004', 175000,
    '{"segment":"retail","preferredLanguage":"da","fictional":true}'
);

INSERT INTO banana_customers (
    customer_id, customer_number, customer_type, legal_name, email,
    phone_number, credit_limit, profile_json
) VALUES (
    NULL, 'B2C-NO-005', 'CONSUMER', 'Fictional Customer Five',
    'customer.five@example.invalid', '+47-555-0105', 0,
    '{"segment":"consumer","marketingConsent":true,"fictional":true}'
);

INSERT INTO banana_addresses (
    address_id, customer_id, address_type, address_line_1, city,
    postal_code, country_code, is_default, valid_from
)
SELECT NULL, customer_id, 'SHIPPING', 'Examplegatan 10', 'Stockholm', '111 20', 'SE', 'Y', DATE '2025-01-01'
  FROM banana_customers WHERE customer_number = 'B2B-NORD-001';
INSERT INTO banana_addresses (
    address_id, customer_id, address_type, address_line_1, city,
    postal_code, country_code, is_default, valid_from
)
SELECT NULL, customer_id, 'BILLING', 'Examplegatan 12', 'Stockholm', '111 20', 'SE', 'Y', DATE '2025-01-01'
  FROM banana_customers WHERE customer_number = 'B2B-NORD-001';
INSERT INTO banana_addresses (
    address_id, customer_id, address_type, address_line_1, city,
    postal_code, country_code, is_default, valid_from
)
SELECT NULL, customer_id, 'SHIPPING', 'Samplekatu 20', 'Helsinki', '00100', 'FI', 'Y', DATE '2025-01-01'
  FROM banana_customers WHERE customer_number = 'B2B-BALT-002';
INSERT INTO banana_addresses (
    address_id, customer_id, address_type, address_line_1, city,
    postal_code, country_code, is_default, valid_from
)
SELECT NULL, customer_id, 'SHIPPING', 'Demovagen 30', 'Uppsala', '753 20', 'SE', 'Y', DATE '2025-01-01'
  FROM banana_customers WHERE customer_number = 'B2C-SE-003';
INSERT INTO banana_addresses (
    address_id, customer_id, address_type, address_line_1, city,
    postal_code, country_code, is_default, valid_from
)
SELECT NULL, customer_id, 'SHIPPING', 'Eksempelvej 40', 'Copenhagen', '1050', 'DK', 'Y', DATE '2025-01-01'
  FROM banana_customers WHERE customer_number = 'B2B-DK-004';
INSERT INTO banana_addresses (
    address_id, customer_id, address_type, address_line_1, city,
    postal_code, country_code, is_default, valid_from
)
SELECT NULL, customer_id, 'SHIPPING', 'Eksempelveien 50', 'Oslo', '0150', 'NO', 'Y', DATE '2025-01-01'
  FROM banana_customers WHERE customer_number = 'B2C-NO-005';

INSERT ALL
    INTO banana_products (product_id, sku, product_name, category, country_of_origin, unit_of_measure, unit_price, tax_rate, shelf_life_days, attributes_json)
        VALUES (NULL, 'BAN-ORG-18', 'Organic Cavendish Bananas - 18 kg', 'FRESH', 'EC', 'CASE', 31.50, 0.1200, 18, '{"grade":"A","organic":true,"fictional":true}')
    INTO banana_products (product_id, sku, product_name, category, country_of_origin, unit_of_measure, unit_price, tax_rate, shelf_life_days, attributes_json)
        VALUES (NULL, 'BAN-STD-18', 'Cavendish Bananas - 18 kg', 'FRESH', 'CR', 'CASE', 24.90, 0.1200, 20, '{"grade":"A","organic":false,"fictional":true}')
    INTO banana_products (product_id, sku, product_name, category, country_of_origin, unit_of_measure, unit_price, tax_rate, shelf_life_days, attributes_json)
        VALUES (NULL, 'BAN-MINI-10', 'Mini Bananas - 10 kg', 'FRESH', 'CO', 'CASE', 28.75, 0.1200, 16, '{"grade":"premium","fictional":true}')
    INTO banana_products (product_id, sku, product_name, category, country_of_origin, unit_of_measure, unit_price, tax_rate, shelf_life_days, attributes_json)
        VALUES (NULL, 'PLT-GRN-20', 'Green Plantains - 20 kg', 'FRESH', 'GT', 'CASE', 35.25, 0.1200, 24, '{"ripeness":"green","fictional":true}')
    INTO banana_products (product_id, sku, product_name, category, country_of_origin, unit_of_measure, unit_price, tax_rate, shelf_life_days, attributes_json)
        VALUES (NULL, 'BAN-CHIP-24', 'Banana Chips - 24 packs', 'DRY_GOODS', 'PH', 'CASE', 42.00, 0.2500, 240, '{"packs":24,"fictional":true}')
    INTO banana_products (product_id, sku, product_name, category, country_of_origin, unit_of_measure, unit_price, tax_rate, shelf_life_days, attributes_json)
        VALUES (NULL, 'BAN-PUREE-12', 'Banana Puree - 12 jars', 'PROCESSED', 'EC', 'CASE', 48.50, 0.1200, 365, '{"jars":12,"fictional":true}')
    INTO banana_products (product_id, sku, product_name, category, country_of_origin, unit_of_measure, unit_price, tax_rate, shelf_life_days, attributes_json)
        VALUES (NULL, 'BOX-REUSE-01', 'Reusable Produce Crate', 'PACKAGING', 'SE', 'EACH', 12.00, 0.2500, NULL, '{"deposit":true,"fictional":true}')
    INTO banana_products (product_id, sku, product_name, category, country_of_origin, unit_of_measure, unit_price, tax_rate, shelf_life_days, attributes_json)
        VALUES (NULL, 'SENSOR-RIPE-1', 'Ripeness Sensor Tag', 'EQUIPMENT', 'SE', 'EACH', 19.95, 0.2500, NULL, '{"bluetooth":true,"fictional":true}')
SELECT 1 FROM dual;

INSERT ALL
    INTO banana_warehouses (warehouse_id, warehouse_code, warehouse_name, country_code, time_zone_region)
        VALUES (NULL, 'STO', 'Stockholm Ripening Centre', 'SE', 'Europe/Stockholm')
    INTO banana_warehouses (warehouse_id, warehouse_code, warehouse_name, country_code, time_zone_region)
        VALUES (NULL, 'HEL', 'Helsinki Distribution Centre', 'FI', 'Europe/Helsinki')
    INTO banana_warehouses (warehouse_id, warehouse_code, warehouse_name, country_code, time_zone_region)
        VALUES (NULL, 'CPH', 'Copenhagen Cross-Dock', 'DK', 'Europe/Copenhagen')
SELECT 1 FROM dual;

INSERT INTO banana_inventory (
    warehouse_id, product_id, quantity_on_hand, quantity_reserved, reorder_point
)
SELECT w.warehouse_id,
       p.product_id,
       CASE w.warehouse_code WHEN 'STO' THEN 2500 WHEN 'HEL' THEN 1800 ELSE 1200 END,
       0,
       CASE p.category WHEN 'FRESH' THEN 300 ELSE 100 END
  FROM banana_warehouses w
 CROSS JOIN banana_products p;

INSERT ALL
    INTO banana_price_rules (price_rule_id, rule_name, customer_type, category, minimum_quantity, discount_percent, valid_from, priority)
        VALUES (1, 'Business fresh produce volume', 'BUSINESS', 'FRESH', 20, 7.50, DATE '2025-01-01', 10)
    INTO banana_price_rules (price_rule_id, rule_name, customer_type, category, minimum_quantity, discount_percent, valid_from, priority)
        VALUES (2, 'Business standard discount', 'BUSINESS', NULL, 10, 4.00, DATE '2025-01-01', 20)
    INTO banana_price_rules (price_rule_id, rule_name, customer_type, category, minimum_quantity, discount_percent, valid_from, priority)
        VALUES (3, 'Bulk packaging discount', NULL, 'PACKAGING', 50, 10.00, DATE '2025-01-01', 5)
SELECT 1 FROM dual;

DECLARE
    TYPE number_list IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
    l_customer_ids number_list;
    l_address_ids  number_list;
    l_product_ids  number_list;
    l_warehouse_ids number_list;
    l_order_id     banana_orders.order_id%TYPE;
    l_customer_ix  PLS_INTEGER;
    l_product_ix   PLS_INTEGER;
    l_warehouse_ix PLS_INTEGER;
    l_line_count   PLS_INTEGER;
BEGIN
    SELECT customer_id BULK COLLECT INTO l_customer_ids
      FROM banana_customers ORDER BY customer_number;
        SELECT a.address_id BULK COLLECT INTO l_address_ids
            FROM banana_addresses a
            JOIN banana_customers c ON c.customer_id = a.customer_id
         WHERE a.address_type = 'SHIPPING'
         ORDER BY c.customer_number;
    SELECT product_id BULK COLLECT INTO l_product_ids
      FROM banana_products ORDER BY sku;
    SELECT warehouse_id BULK COLLECT INTO l_warehouse_ids
      FROM banana_warehouses ORDER BY warehouse_code;

    DBMS_RANDOM.SEED(20260902);

    FOR order_index IN 1..120 LOOP
        l_customer_ix := MOD(order_index - 1, l_customer_ids.COUNT) + 1;
        l_warehouse_ix := MOD(order_index - 1, l_warehouse_ids.COUNT) + 1;

        banana_commerce_api.create_order(
            p_customer_id => l_customer_ids(l_customer_ix),
            p_shipping_address_id => l_address_ids(l_customer_ix),
            p_source_channel => CASE MOD(order_index, 4)
                WHEN 0 THEN 'EDI' WHEN 1 THEN 'WEB'
                WHEN 2 THEN 'MOBILE' ELSE 'CALL_CENTRE' END,
            p_requested_date => DATE '2026-09-10' + MOD(order_index, 21),
            p_correlation_id => 'fictional-correlation-' || LPAD(order_index, 4, '0'),
            p_order_date => DATE '2026-06-01' + MOD(order_index * 3, 92),
            p_order_id => l_order_id
        );

        l_line_count := MOD(order_index, 3) + 1;
        FOR line_index IN 1..l_line_count LOOP
            l_product_ix := MOD(order_index + line_index - 2, l_product_ids.COUNT) + 1;
            banana_commerce_api.add_order_line(
                p_order_id => l_order_id,
                p_product_id => l_product_ids(l_product_ix),
                p_warehouse_id => l_warehouse_ids(l_warehouse_ix),
                p_quantity => MOD(order_index * line_index, 24) + 1
            );
        END LOOP;

        IF MOD(order_index, 4) <> 0 THEN
            banana_commerce_api.reserve_order(l_order_id);

            IF MOD(order_index, 3) = 0 THEN
                banana_commerce_api.capture_payment(
                    l_order_id,
                    'FICTIONAL-PAY-' || LPAD(order_index, 6, '0'),
                    CASE MOD(order_index, 2) WHEN 0 THEN 'INVOICE' ELSE 'CARD' END
                );

                IF MOD(order_index, 10) = 0 THEN
                    banana_commerce_api.ship_order(
                        l_order_id,
                        l_warehouse_ids(l_warehouse_ix),
                        'BANANA-EXPRESS',
                        'FICTIONAL-TRACK-' || LPAD(order_index, 6, '0')
                    );
                END IF;
            ELSIF MOD(order_index, 11) = 0 THEN
                banana_commerce_api.cancel_order(
                    l_order_id,
                    'Fictional customer cancellation for migration testing'
                );
            END IF;
        END IF;
    END LOOP;
END;
/

COMMIT;
PROMPT Fictional Banana Commerce data loaded.