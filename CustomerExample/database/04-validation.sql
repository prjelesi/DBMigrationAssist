WHENEVER SQLERROR EXIT SQL.SQLCODE
SET DEFINE OFF
SET SERVEROUTPUT ON

PROMPT Validating Banana Commerce installation...

DECLARE
    l_count NUMBER;

    PROCEDURE assert_count (
        p_description IN VARCHAR2,
        p_actual      IN NUMBER,
        p_expected    IN NUMBER
    ) IS
    BEGIN
        IF p_actual <> p_expected THEN
            RAISE_APPLICATION_ERROR(
                -20100,
                p_description || ': expected ' || p_expected || ', found ' || p_actual
            );
        END IF;
        DBMS_OUTPUT.PUT_LINE('PASS: ' || p_description || ' = ' || p_actual);
    END assert_count;
BEGIN
    SELECT COUNT(*) INTO l_count FROM banana_customers;
    assert_count('customers', l_count, 5);

    SELECT COUNT(*) INTO l_count FROM banana_addresses;
    assert_count('addresses', l_count, 6);

    SELECT COUNT(*) INTO l_count FROM banana_products;
    assert_count('products', l_count, 8);

    SELECT COUNT(*) INTO l_count FROM banana_warehouses;
    assert_count('warehouses', l_count, 3);

    SELECT COUNT(*) INTO l_count FROM banana_inventory;
    assert_count('inventory positions', l_count, 24);

    SELECT COUNT(*) INTO l_count FROM banana_orders;
    assert_count('orders', l_count, 120);

    SELECT COUNT(*) INTO l_count
      FROM banana_orders
     WHERE total_amount <= 0;
    assert_count('orders with invalid totals', l_count, 0);

    SELECT COUNT(*) INTO l_count
      FROM banana_inventory
     WHERE quantity_on_hand < 0
        OR quantity_reserved < 0
        OR quantity_reserved > quantity_on_hand;
    assert_count('invalid inventory positions', l_count, 0);

    SELECT COUNT(*) INTO l_count
      FROM banana_orders o
     WHERE status IN ('RESERVED', 'PAID')
       AND NOT EXISTS (
           SELECT 1 FROM banana_order_lines l
            WHERE l.order_id = o.order_id
              AND l.fulfilment_status = 'RESERVED'
       );
    assert_count('active orders without reservations', l_count, 0);

    SELECT COUNT(*) INTO l_count
      FROM user_errors
     WHERE name LIKE 'BANANA_%';
    assert_count('PL/SQL compilation errors', l_count, 0);

    SELECT COUNT(*) INTO l_count
      FROM user_objects
     WHERE object_name LIKE 'BANANA_%'
       AND status <> 'VALID';
    assert_count('invalid schema objects', l_count, 0);
END;
/

PROMPT Order status distribution:
SELECT status, COUNT(*) AS order_count, ROUND(SUM(total_amount), 2) AS total_value
  FROM banana_orders
 GROUP BY status
 ORDER BY status;

PROMPT Partition distribution:
SELECT partition_name, num_rows
  FROM user_tab_partitions
 WHERE table_name = 'BANANA_ORDERS'
 ORDER BY partition_position;

PROMPT Banana Commerce installation is valid.