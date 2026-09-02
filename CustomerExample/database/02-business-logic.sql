WHENEVER SQLERROR EXIT SQL.SQLCODE
SET DEFINE OFF
SET SERVEROUTPUT ON

PROMPT Creating Banana Commerce triggers, package and views...

CREATE OR REPLACE TRIGGER banana_customers_biu
BEFORE INSERT OR UPDATE ON banana_customers
FOR EACH ROW
BEGIN
    IF INSERTING AND :NEW.customer_id IS NULL THEN
        :NEW.customer_id := banana_customer_seq.NEXTVAL;
    END IF;
    IF INSERTING THEN
        :NEW.created_at := SYSTIMESTAMP;
    END IF;
    :NEW.updated_at := SYSTIMESTAMP;
END;
/

CREATE OR REPLACE TRIGGER banana_addresses_bi
BEFORE INSERT ON banana_addresses
FOR EACH ROW
BEGIN
    IF :NEW.address_id IS NULL THEN
        :NEW.address_id := banana_address_seq.NEXTVAL;
    END IF;
END;
/

CREATE OR REPLACE TRIGGER banana_products_biu
BEFORE INSERT OR UPDATE ON banana_products
FOR EACH ROW
BEGIN
    IF INSERTING AND :NEW.product_id IS NULL THEN
        :NEW.product_id := banana_product_seq.NEXTVAL;
    END IF;
    IF INSERTING THEN
        :NEW.created_at := SYSTIMESTAMP;
    END IF;
    :NEW.updated_at := SYSTIMESTAMP;
END;
/

CREATE OR REPLACE TRIGGER banana_warehouses_bi
BEFORE INSERT ON banana_warehouses
FOR EACH ROW
BEGIN
    IF :NEW.warehouse_id IS NULL THEN
        :NEW.warehouse_id := banana_warehouse_seq.NEXTVAL;
    END IF;
END;
/

CREATE OR REPLACE TRIGGER banana_inventory_bu
BEFORE UPDATE ON banana_inventory
FOR EACH ROW
BEGIN
    :NEW.version_number := :OLD.version_number + 1;
    :NEW.updated_at := SYSTIMESTAMP;
END;
/

CREATE OR REPLACE TRIGGER banana_orders_biu
BEFORE INSERT OR UPDATE ON banana_orders
FOR EACH ROW
BEGIN
    IF INSERTING THEN
        IF :NEW.order_id IS NULL THEN
            :NEW.order_id := banana_order_seq.NEXTVAL;
        END IF;
        IF :NEW.order_number IS NULL THEN
            :NEW.order_number := 'BN-' || TO_CHAR(:NEW.order_date, 'YYYY') || '-'
                || LPAD(TO_CHAR(:NEW.order_id), 8, '0');
        END IF;
        :NEW.created_at := SYSTIMESTAMP;
    END IF;
    :NEW.updated_at := SYSTIMESTAMP;
END;
/

CREATE OR REPLACE TRIGGER banana_order_lines_bi
BEFORE INSERT OR UPDATE OF quantity, unit_price, discount_percent, tax_rate
ON banana_order_lines
FOR EACH ROW
BEGIN
    IF INSERTING AND :NEW.order_line_id IS NULL THEN
        :NEW.order_line_id := banana_order_line_seq.NEXTVAL;
    END IF;
    :NEW.line_total := ROUND(
        :NEW.quantity * :NEW.unit_price
        * (1 - (:NEW.discount_percent / 100))
        * (1 + :NEW.tax_rate),
        2
    );
END;
/

CREATE OR REPLACE TRIGGER banana_payments_bi
BEFORE INSERT ON banana_payments
FOR EACH ROW
BEGIN
    IF :NEW.payment_id IS NULL THEN
        :NEW.payment_id := banana_payment_seq.NEXTVAL;
    END IF;
END;
/

CREATE OR REPLACE TRIGGER banana_shipments_bi
BEFORE INSERT ON banana_shipments
FOR EACH ROW
BEGIN
    IF :NEW.shipment_id IS NULL THEN
        :NEW.shipment_id := banana_shipment_seq.NEXTVAL;
    END IF;
END;
/

CREATE OR REPLACE TRIGGER banana_orders_audit_au
AFTER UPDATE OF status, total_amount ON banana_orders
FOR EACH ROW
WHEN (OLD.status <> NEW.status OR OLD.total_amount <> NEW.total_amount)
BEGIN
    INSERT INTO banana_order_audit (
        audit_id, order_id, old_status, new_status,
        old_total_amount, new_total_amount, change_reason
    ) VALUES (
        banana_audit_seq.NEXTVAL, :NEW.order_id, :OLD.status, :NEW.status,
        :OLD.total_amount, :NEW.total_amount,
        SYS_CONTEXT('BANANA_CONTEXT', 'CHANGE_REASON')
    );
END;
/

CREATE OR REPLACE PACKAGE banana_commerce_api AS
    PROCEDURE create_order (
        p_customer_id         IN  banana_customers.customer_id%TYPE,
        p_shipping_address_id IN  banana_addresses.address_id%TYPE,
        p_source_channel      IN  banana_orders.source_channel%TYPE,
        p_requested_date      IN  DATE,
        p_correlation_id      IN  banana_orders.correlation_id%TYPE,
        p_order_date          IN  DATE DEFAULT SYSDATE,
        p_order_id            OUT banana_orders.order_id%TYPE
    );

    PROCEDURE add_order_line (
        p_order_id      IN banana_orders.order_id%TYPE,
        p_product_id    IN banana_products.product_id%TYPE,
        p_warehouse_id  IN banana_warehouses.warehouse_id%TYPE,
        p_quantity      IN banana_order_lines.quantity%TYPE
    );

    PROCEDURE reserve_order (
        p_order_id IN banana_orders.order_id%TYPE
    );

    PROCEDURE capture_payment (
        p_order_id          IN banana_orders.order_id%TYPE,
        p_provider_reference IN banana_payments.provider_reference%TYPE,
        p_payment_method     IN banana_payments.payment_method%TYPE
    );

    PROCEDURE ship_order (
        p_order_id       IN banana_orders.order_id%TYPE,
        p_warehouse_id   IN banana_warehouses.warehouse_id%TYPE,
        p_carrier_code   IN banana_shipments.carrier_code%TYPE,
        p_tracking_number IN banana_shipments.tracking_number%TYPE
    );

    PROCEDURE cancel_order (
        p_order_id IN banana_orders.order_id%TYPE,
        p_reason   IN VARCHAR2
    );
END banana_commerce_api;
/

CREATE OR REPLACE PACKAGE BODY banana_commerce_api AS
    PROCEDURE set_change_reason (p_reason IN VARCHAR2) IS
    BEGIN
        DBMS_SESSION.SET_CONTEXT('BANANA_CONTEXT', 'CHANGE_REASON', SUBSTR(p_reason, 1, 500));
    EXCEPTION
        WHEN OTHERS THEN
            NULL;
    END set_change_reason;

    PROCEDURE emit_event (
        p_aggregate_id   IN VARCHAR2,
        p_event_type     IN VARCHAR2,
        p_payload_json   IN CLOB,
        p_correlation_id IN VARCHAR2
    ) IS
    BEGIN
        INSERT INTO banana_outbox_events (
            event_id, aggregate_type, aggregate_id, event_type,
            payload_json, correlation_id
        ) VALUES (
            banana_event_seq.NEXTVAL, 'ORDER', p_aggregate_id, p_event_type,
            p_payload_json, p_correlation_id
        );
    END emit_event;

    FUNCTION applicable_discount (
        p_customer_type IN banana_customers.customer_type%TYPE,
        p_category      IN banana_products.category%TYPE,
        p_quantity      IN banana_order_lines.quantity%TYPE,
        p_order_date    IN DATE
    ) RETURN NUMBER IS
        l_discount banana_price_rules.discount_percent%TYPE;
    BEGIN
        SELECT NVL(MAX(discount_percent) KEEP (DENSE_RANK FIRST ORDER BY priority), 0)
          INTO l_discount
          FROM banana_price_rules
         WHERE active_flag = 'Y'
           AND (customer_type IS NULL OR customer_type = p_customer_type)
           AND (category IS NULL OR category = p_category)
           AND minimum_quantity <= p_quantity
           AND valid_from <= p_order_date
           AND (valid_to IS NULL OR valid_to >= p_order_date);
        RETURN l_discount;
    END applicable_discount;

    PROCEDURE recalculate_order (p_order_id IN banana_orders.order_id%TYPE) IS
    BEGIN
        UPDATE banana_orders o
           SET (subtotal_amount, discount_amount, tax_amount, total_amount) = (
               SELECT NVL(SUM(quantity * unit_price), 0),
                      NVL(SUM(quantity * unit_price * discount_percent / 100), 0),
                      NVL(SUM(
                          quantity * unit_price * (1 - discount_percent / 100) * tax_rate
                      ), 0),
                      NVL(SUM(line_total), 0)
                 FROM banana_order_lines l
                WHERE l.order_id = o.order_id
           )
         WHERE o.order_id = p_order_id;
    END recalculate_order;

    PROCEDURE create_order (
        p_customer_id         IN  banana_customers.customer_id%TYPE,
        p_shipping_address_id IN  banana_addresses.address_id%TYPE,
        p_source_channel      IN  banana_orders.source_channel%TYPE,
        p_requested_date      IN  DATE,
        p_correlation_id      IN  banana_orders.correlation_id%TYPE,
        p_order_date          IN  DATE DEFAULT SYSDATE,
        p_order_id            OUT banana_orders.order_id%TYPE
    ) IS
        l_count NUMBER;
    BEGIN
        SELECT COUNT(*)
          INTO l_count
          FROM banana_addresses
         WHERE address_id = p_shipping_address_id
           AND customer_id = p_customer_id
           AND address_type = 'SHIPPING'
           AND valid_from <= p_order_date
           AND (valid_to IS NULL OR valid_to >= p_order_date);

        IF l_count = 0 THEN
            RAISE_APPLICATION_ERROR(-20001, 'Shipping address is not valid for this customer.');
        END IF;

        INSERT INTO banana_orders (
            order_id, order_number, customer_id, shipping_address_id,
            order_date, requested_date, source_channel, correlation_id
        ) VALUES (
            NULL, NULL, p_customer_id, p_shipping_address_id,
            p_order_date, p_requested_date, p_source_channel, p_correlation_id
        ) RETURNING order_id INTO p_order_id;

        emit_event(
            TO_CHAR(p_order_id), 'OrderCreated',
            JSON_OBJECT(
                'orderId' VALUE p_order_id,
                'customerId' VALUE p_customer_id,
                'channel' VALUE p_source_channel RETURNING CLOB
            ),
            p_correlation_id
        );
    END create_order;

    PROCEDURE add_order_line (
        p_order_id      IN banana_orders.order_id%TYPE,
        p_product_id    IN banana_products.product_id%TYPE,
        p_warehouse_id  IN banana_warehouses.warehouse_id%TYPE,
        p_quantity      IN banana_order_lines.quantity%TYPE
    ) IS
        l_status        banana_orders.status%TYPE;
        l_order_date    banana_orders.order_date%TYPE;
        l_customer_type banana_customers.customer_type%TYPE;
        l_unit_price    banana_products.unit_price%TYPE;
        l_tax_rate      banana_products.tax_rate%TYPE;
        l_category      banana_products.category%TYPE;
        l_line_number   banana_order_lines.line_number%TYPE;
        l_discount      banana_price_rules.discount_percent%TYPE;
    BEGIN
        SELECT o.status, o.order_date, c.customer_type
          INTO l_status, l_order_date, l_customer_type
          FROM banana_orders o
          JOIN banana_customers c ON c.customer_id = o.customer_id
         WHERE o.order_id = p_order_id
         FOR UPDATE OF o.status;

        IF l_status <> 'DRAFT' THEN
            RAISE_APPLICATION_ERROR(-20002, 'Lines can only be added to a draft order.');
        END IF;

        SELECT unit_price, tax_rate, category
          INTO l_unit_price, l_tax_rate, l_category
          FROM banana_products
         WHERE product_id = p_product_id
           AND status = 'ACTIVE';

        SELECT NVL(MAX(line_number), 0) + 1
          INTO l_line_number
          FROM banana_order_lines
         WHERE order_id = p_order_id;

        l_discount := applicable_discount(
            l_customer_type, l_category, p_quantity, l_order_date
        );

        INSERT INTO banana_order_lines (
            order_line_id, order_id, line_number, product_id, warehouse_id,
            quantity, unit_price, discount_percent, tax_rate, line_total
        ) VALUES (
            NULL, p_order_id, l_line_number, p_product_id, p_warehouse_id,
            p_quantity, l_unit_price, l_discount, l_tax_rate, 0
        );

        recalculate_order(p_order_id);
    END add_order_line;

    PROCEDURE reserve_order (p_order_id IN banana_orders.order_id%TYPE) IS
        l_status         banana_orders.status%TYPE;
        l_correlation_id banana_orders.correlation_id%TYPE;
        l_line_count     NUMBER;
    BEGIN
        SELECT status, correlation_id
          INTO l_status, l_correlation_id
          FROM banana_orders
         WHERE order_id = p_order_id
         FOR UPDATE;

        IF l_status <> 'DRAFT' THEN
            RAISE_APPLICATION_ERROR(-20003, 'Only a draft order can be reserved.');
        END IF;

        SELECT COUNT(*) INTO l_line_count
          FROM banana_order_lines
         WHERE order_id = p_order_id;
        IF l_line_count = 0 THEN
            RAISE_APPLICATION_ERROR(-20004, 'An order must contain at least one line.');
        END IF;

        FOR line_record IN (
            SELECT order_line_id, warehouse_id, product_id, quantity
              FROM banana_order_lines
             WHERE order_id = p_order_id
             ORDER BY warehouse_id, product_id
        ) LOOP
            UPDATE banana_inventory
               SET quantity_reserved = quantity_reserved + line_record.quantity
             WHERE warehouse_id = line_record.warehouse_id
               AND product_id = line_record.product_id
               AND quantity_on_hand - quantity_reserved >= line_record.quantity;

            IF SQL%ROWCOUNT = 0 THEN
                RAISE_APPLICATION_ERROR(
                    -20005,
                    'Insufficient inventory for product ' || line_record.product_id
                        || ' at warehouse ' || line_record.warehouse_id
                );
            END IF;

            UPDATE banana_order_lines
               SET fulfilment_status = 'RESERVED'
             WHERE order_line_id = line_record.order_line_id;
        END LOOP;

        set_change_reason('Inventory reserved');
        UPDATE banana_orders SET status = 'RESERVED' WHERE order_id = p_order_id;
        emit_event(
            TO_CHAR(p_order_id), 'OrderReserved',
            JSON_OBJECT('orderId' VALUE p_order_id, 'lineCount' VALUE l_line_count RETURNING CLOB),
            l_correlation_id
        );
    END reserve_order;

    PROCEDURE capture_payment (
        p_order_id           IN banana_orders.order_id%TYPE,
        p_provider_reference IN banana_payments.provider_reference%TYPE,
        p_payment_method     IN banana_payments.payment_method%TYPE
    ) IS
        l_status         banana_orders.status%TYPE;
        l_total          banana_orders.total_amount%TYPE;
        l_currency       banana_orders.currency_code%TYPE;
        l_correlation_id banana_orders.correlation_id%TYPE;
    BEGIN
        SELECT status, total_amount, currency_code, correlation_id
          INTO l_status, l_total, l_currency, l_correlation_id
          FROM banana_orders
         WHERE order_id = p_order_id
         FOR UPDATE;

        IF l_status <> 'RESERVED' THEN
            RAISE_APPLICATION_ERROR(-20006, 'Payment requires a reserved order.');
        END IF;

        INSERT INTO banana_payments (
            payment_id, order_id, provider_reference, payment_method,
            amount, currency_code, status, paid_at, metadata_json
        ) VALUES (
            NULL, p_order_id, p_provider_reference, p_payment_method,
            l_total, l_currency, 'CAPTURED', SYSTIMESTAMP,
            JSON_OBJECT('fictional' VALUE 'true', 'provider' VALUE 'BANANA_PAY' RETURNING CLOB)
        );

        set_change_reason('Payment captured');
        UPDATE banana_orders SET status = 'PAID' WHERE order_id = p_order_id;
        emit_event(
            TO_CHAR(p_order_id), 'PaymentCaptured',
            JSON_OBJECT('orderId' VALUE p_order_id, 'amount' VALUE l_total RETURNING CLOB),
            l_correlation_id
        );
    END capture_payment;

    PROCEDURE ship_order (
        p_order_id        IN banana_orders.order_id%TYPE,
        p_warehouse_id    IN banana_warehouses.warehouse_id%TYPE,
        p_carrier_code    IN banana_shipments.carrier_code%TYPE,
        p_tracking_number IN banana_shipments.tracking_number%TYPE
    ) IS
        l_status         banana_orders.status%TYPE;
        l_correlation_id banana_orders.correlation_id%TYPE;
        l_other_count    NUMBER;
    BEGIN
        SELECT status, correlation_id
          INTO l_status, l_correlation_id
          FROM banana_orders
         WHERE order_id = p_order_id
         FOR UPDATE;

        IF l_status <> 'PAID' THEN
            RAISE_APPLICATION_ERROR(-20007, 'Shipping requires a paid order.');
        END IF;

        SELECT COUNT(*) INTO l_other_count
          FROM banana_order_lines
         WHERE order_id = p_order_id
           AND warehouse_id <> p_warehouse_id;
        IF l_other_count > 0 THEN
            RAISE_APPLICATION_ERROR(-20008, 'The example ships an order from one warehouse.');
        END IF;

        FOR line_record IN (
            SELECT order_line_id, product_id, quantity
              FROM banana_order_lines
             WHERE order_id = p_order_id
               AND warehouse_id = p_warehouse_id
               AND fulfilment_status = 'RESERVED'
             ORDER BY product_id
        ) LOOP
            UPDATE banana_inventory
               SET quantity_on_hand = quantity_on_hand - line_record.quantity,
                   quantity_reserved = quantity_reserved - line_record.quantity
             WHERE warehouse_id = p_warehouse_id
               AND product_id = line_record.product_id;

            UPDATE banana_order_lines
               SET fulfilment_status = 'SHIPPED'
             WHERE order_line_id = line_record.order_line_id;
        END LOOP;

        INSERT INTO banana_shipments (
            shipment_id, order_id, warehouse_id, carrier_code,
            tracking_number, status, shipped_at
        ) VALUES (
            NULL, p_order_id, p_warehouse_id, p_carrier_code,
            p_tracking_number, 'DISPATCHED', SYSTIMESTAMP
        );

        set_change_reason('Shipment dispatched');
        UPDATE banana_orders SET status = 'SHIPPED' WHERE order_id = p_order_id;
        emit_event(
            TO_CHAR(p_order_id), 'OrderShipped',
            JSON_OBJECT(
                'orderId' VALUE p_order_id,
                'warehouseId' VALUE p_warehouse_id,
                'trackingNumber' VALUE p_tracking_number RETURNING CLOB
            ),
            l_correlation_id
        );
    END ship_order;

    PROCEDURE cancel_order (
        p_order_id IN banana_orders.order_id%TYPE,
        p_reason   IN VARCHAR2
    ) IS
        l_status         banana_orders.status%TYPE;
        l_correlation_id banana_orders.correlation_id%TYPE;
    BEGIN
        SELECT status, correlation_id
          INTO l_status, l_correlation_id
          FROM banana_orders
         WHERE order_id = p_order_id
         FOR UPDATE;

        IF l_status NOT IN ('DRAFT', 'RESERVED') THEN
            RAISE_APPLICATION_ERROR(-20009, 'Only draft or reserved orders can be cancelled.');
        END IF;

        IF l_status = 'RESERVED' THEN
            FOR line_record IN (
                SELECT order_line_id, warehouse_id, product_id, quantity
                  FROM banana_order_lines
                 WHERE order_id = p_order_id
                   AND fulfilment_status = 'RESERVED'
            ) LOOP
                UPDATE banana_inventory
                   SET quantity_reserved = quantity_reserved - line_record.quantity
                 WHERE warehouse_id = line_record.warehouse_id
                   AND product_id = line_record.product_id;
                UPDATE banana_order_lines
                   SET fulfilment_status = 'CANCELLED'
                 WHERE order_line_id = line_record.order_line_id;
            END LOOP;
        ELSE
            UPDATE banana_order_lines
               SET fulfilment_status = 'CANCELLED'
             WHERE order_id = p_order_id;
        END IF;

        set_change_reason(NVL(p_reason, 'Order cancelled'));
        UPDATE banana_orders
           SET status = 'CANCELLED', notes = SUBSTR(p_reason, 1, 1000)
         WHERE order_id = p_order_id;
        emit_event(
            TO_CHAR(p_order_id), 'OrderCancelled',
            JSON_OBJECT('orderId' VALUE p_order_id, 'reason' VALUE p_reason RETURNING CLOB),
            l_correlation_id
        );
    END cancel_order;
END banana_commerce_api;
/

CREATE OR REPLACE VIEW banana_v_order_summary AS
SELECT o.order_id,
       o.order_number,
       o.order_date,
       o.status,
       c.customer_number,
       c.legal_name,
       COUNT(l.order_line_id) AS line_count,
       SUM(l.quantity) AS item_count,
       o.currency_code,
       o.total_amount,
       o.source_channel
  FROM banana_orders o
  JOIN banana_customers c ON c.customer_id = o.customer_id
  LEFT JOIN banana_order_lines l ON l.order_id = o.order_id
 GROUP BY o.order_id, o.order_number, o.order_date, o.status,
          c.customer_number, c.legal_name, o.currency_code,
          o.total_amount, o.source_channel;

CREATE OR REPLACE VIEW banana_v_inventory_risk AS
SELECT w.warehouse_code,
       p.sku,
       p.product_name,
       i.quantity_on_hand,
       i.quantity_reserved,
       i.quantity_on_hand - i.quantity_reserved AS available_quantity,
       i.reorder_point,
       CASE
           WHEN i.quantity_on_hand - i.quantity_reserved <= i.reorder_point THEN 'REORDER'
           ELSE 'HEALTHY'
       END AS stock_status
  FROM banana_inventory i
  JOIN banana_warehouses w ON w.warehouse_id = i.warehouse_id
  JOIN banana_products p ON p.product_id = i.product_id;

CREATE OR REPLACE VIEW banana_v_daily_sales AS
SELECT TRUNC(order_date) AS sales_date,
       currency_code,
       source_channel,
       COUNT(*) AS order_count,
       SUM(total_amount) AS gross_sales,
       SUM(discount_amount) AS discounts,
       SUM(tax_amount) AS tax_amount
  FROM banana_orders
 WHERE status IN ('PAID', 'PICKING', 'SHIPPED')
 GROUP BY TRUNC(order_date), currency_code, source_channel;

PROMPT Banana Commerce business logic created.