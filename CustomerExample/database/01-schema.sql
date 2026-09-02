WHENEVER SQLERROR EXIT SQL.SQLCODE
SET DEFINE OFF
SET SERVEROUTPUT ON

PROMPT Creating Banana Commerce Oracle schema...

CREATE SEQUENCE banana_customer_seq START WITH 1001 CACHE 50;
CREATE SEQUENCE banana_address_seq START WITH 2001 CACHE 50;
CREATE SEQUENCE banana_product_seq START WITH 3001 CACHE 50;
CREATE SEQUENCE banana_warehouse_seq START WITH 4001 CACHE 20;
CREATE SEQUENCE banana_order_seq START WITH 100001 CACHE 100;
CREATE SEQUENCE banana_order_line_seq START WITH 200001 CACHE 100;
CREATE SEQUENCE banana_payment_seq START WITH 300001 CACHE 50;
CREATE SEQUENCE banana_shipment_seq START WITH 400001 CACHE 50;
CREATE SEQUENCE banana_event_seq START WITH 500001 CACHE 100;
CREATE SEQUENCE banana_audit_seq START WITH 600001 CACHE 100;

CREATE TABLE banana_customers (
    customer_id       NUMBER(12)       NOT NULL,
    customer_number   VARCHAR2(30 CHAR) NOT NULL,
    customer_type     VARCHAR2(20 CHAR) DEFAULT 'BUSINESS' NOT NULL,
    legal_name        VARCHAR2(200 CHAR) NOT NULL,
    email             VARCHAR2(254 CHAR),
    phone_number      VARCHAR2(40 CHAR),
    tax_identifier    VARCHAR2(50 CHAR),
    credit_limit      NUMBER(15,2)     DEFAULT 0 NOT NULL,
    status            VARCHAR2(20 CHAR) DEFAULT 'ACTIVE' NOT NULL,
    profile_json      CLOB,
    created_at        TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    updated_at        TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_banana_customers PRIMARY KEY (customer_id),
    CONSTRAINT uq_banana_customer_number UNIQUE (customer_number),
    CONSTRAINT uq_banana_customer_email UNIQUE (email),
    CONSTRAINT ck_banana_customer_type CHECK (customer_type IN ('BUSINESS', 'CONSUMER')),
    CONSTRAINT ck_banana_customer_status CHECK (status IN ('ACTIVE', 'ON_HOLD', 'CLOSED')),
    CONSTRAINT ck_banana_credit_limit CHECK (credit_limit >= 0),
    CONSTRAINT ck_banana_profile_json CHECK (profile_json IS JSON)
);

CREATE TABLE banana_addresses (
    address_id        NUMBER(12)       NOT NULL,
    customer_id       NUMBER(12)       NOT NULL,
    address_type      VARCHAR2(20 CHAR) NOT NULL,
    address_line_1    VARCHAR2(200 CHAR) NOT NULL,
    address_line_2    VARCHAR2(200 CHAR),
    city              VARCHAR2(100 CHAR) NOT NULL,
    postal_code       VARCHAR2(20 CHAR) NOT NULL,
    country_code      CHAR(2 CHAR)     NOT NULL,
    is_default        CHAR(1 CHAR)     DEFAULT 'N' NOT NULL,
    valid_from        DATE             DEFAULT TRUNC(SYSDATE) NOT NULL,
    valid_to          DATE,
    CONSTRAINT pk_banana_addresses PRIMARY KEY (address_id),
    CONSTRAINT fk_banana_address_customer FOREIGN KEY (customer_id)
        REFERENCES banana_customers (customer_id),
    CONSTRAINT ck_banana_address_type CHECK (address_type IN ('BILLING', 'SHIPPING')),
    CONSTRAINT ck_banana_address_default CHECK (is_default IN ('Y', 'N')),
    CONSTRAINT ck_banana_address_dates CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE banana_products (
    product_id        NUMBER(12)       NOT NULL,
    sku               VARCHAR2(40 CHAR) NOT NULL,
    product_name      VARCHAR2(200 CHAR) NOT NULL,
    category          VARCHAR2(50 CHAR) NOT NULL,
    country_of_origin CHAR(2 CHAR),
    unit_of_measure   VARCHAR2(10 CHAR) DEFAULT 'CASE' NOT NULL,
    unit_price        NUMBER(12,2)     NOT NULL,
    tax_rate          NUMBER(5,4)      DEFAULT 0 NOT NULL,
    shelf_life_days   NUMBER(5),
    attributes_json   CLOB,
    status            VARCHAR2(20 CHAR) DEFAULT 'ACTIVE' NOT NULL,
    created_at        TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    updated_at        TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_banana_products PRIMARY KEY (product_id),
    CONSTRAINT uq_banana_product_sku UNIQUE (sku),
    CONSTRAINT ck_banana_product_price CHECK (unit_price >= 0),
    CONSTRAINT ck_banana_product_tax CHECK (tax_rate BETWEEN 0 AND 1),
    CONSTRAINT ck_banana_product_status CHECK (status IN ('ACTIVE', 'DISCONTINUED')),
    CONSTRAINT ck_banana_product_json CHECK (attributes_json IS JSON)
);

CREATE TABLE banana_price_rules (
    price_rule_id     NUMBER(12)       NOT NULL,
    rule_name         VARCHAR2(100 CHAR) NOT NULL,
    customer_type     VARCHAR2(20 CHAR),
    category          VARCHAR2(50 CHAR),
    minimum_quantity  NUMBER(10)       DEFAULT 1 NOT NULL,
    discount_percent  NUMBER(5,2)      NOT NULL,
    valid_from        DATE             NOT NULL,
    valid_to          DATE,
    priority          NUMBER(4)        DEFAULT 100 NOT NULL,
    active_flag       CHAR(1 CHAR)     DEFAULT 'Y' NOT NULL,
    CONSTRAINT pk_banana_price_rules PRIMARY KEY (price_rule_id),
    CONSTRAINT uq_banana_price_rule_name UNIQUE (rule_name),
    CONSTRAINT ck_banana_rule_customer_type CHECK (customer_type IS NULL OR customer_type IN ('BUSINESS', 'CONSUMER')),
    CONSTRAINT ck_banana_rule_quantity CHECK (minimum_quantity > 0),
    CONSTRAINT ck_banana_rule_discount CHECK (discount_percent BETWEEN 0 AND 100),
    CONSTRAINT ck_banana_rule_dates CHECK (valid_to IS NULL OR valid_to >= valid_from),
    CONSTRAINT ck_banana_rule_active CHECK (active_flag IN ('Y', 'N'))
);

CREATE TABLE banana_warehouses (
    warehouse_id      NUMBER(12)       NOT NULL,
    warehouse_code    VARCHAR2(20 CHAR) NOT NULL,
    warehouse_name    VARCHAR2(100 CHAR) NOT NULL,
    country_code      CHAR(2 CHAR)     NOT NULL,
    time_zone_region  VARCHAR2(64 CHAR) NOT NULL,
    active_flag       CHAR(1 CHAR)     DEFAULT 'Y' NOT NULL,
    CONSTRAINT pk_banana_warehouses PRIMARY KEY (warehouse_id),
    CONSTRAINT uq_banana_warehouse_code UNIQUE (warehouse_code),
    CONSTRAINT ck_banana_warehouse_active CHECK (active_flag IN ('Y', 'N'))
);

CREATE TABLE banana_inventory (
    warehouse_id      NUMBER(12)       NOT NULL,
    product_id        NUMBER(12)       NOT NULL,
    quantity_on_hand  NUMBER(12)       DEFAULT 0 NOT NULL,
    quantity_reserved NUMBER(12)       DEFAULT 0 NOT NULL,
    reorder_point     NUMBER(12)       DEFAULT 0 NOT NULL,
    version_number    NUMBER(10)       DEFAULT 1 NOT NULL,
    updated_at        TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_banana_inventory PRIMARY KEY (warehouse_id, product_id),
    CONSTRAINT fk_banana_inventory_warehouse FOREIGN KEY (warehouse_id)
        REFERENCES banana_warehouses (warehouse_id),
    CONSTRAINT fk_banana_inventory_product FOREIGN KEY (product_id)
        REFERENCES banana_products (product_id),
    CONSTRAINT ck_banana_inventory_values CHECK (
        quantity_on_hand >= 0 AND quantity_reserved >= 0
        AND quantity_reserved <= quantity_on_hand AND reorder_point >= 0
    )
);

CREATE TABLE banana_orders (
    order_id          NUMBER(14)       NOT NULL,
    order_number      VARCHAR2(30 CHAR) NOT NULL,
    customer_id       NUMBER(12)       NOT NULL,
    shipping_address_id NUMBER(12)     NOT NULL,
    order_date        DATE             DEFAULT SYSDATE NOT NULL,
    requested_date    DATE,
    status            VARCHAR2(20 CHAR) DEFAULT 'DRAFT' NOT NULL,
    currency_code     CHAR(3 CHAR)     DEFAULT 'EUR' NOT NULL,
    subtotal_amount   NUMBER(15,2)     DEFAULT 0 NOT NULL,
    discount_amount   NUMBER(15,2)     DEFAULT 0 NOT NULL,
    tax_amount        NUMBER(15,2)     DEFAULT 0 NOT NULL,
    total_amount      NUMBER(15,2)     DEFAULT 0 NOT NULL,
    source_channel    VARCHAR2(20 CHAR) DEFAULT 'WEB' NOT NULL,
    correlation_id    VARCHAR2(64 CHAR),
    notes             VARCHAR2(1000 CHAR),
    created_at        TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    updated_at        TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_banana_orders PRIMARY KEY (order_id),
    CONSTRAINT uq_banana_order_number UNIQUE (order_number),
    CONSTRAINT fk_banana_order_customer FOREIGN KEY (customer_id)
        REFERENCES banana_customers (customer_id),
    CONSTRAINT fk_banana_order_address FOREIGN KEY (shipping_address_id)
        REFERENCES banana_addresses (address_id),
    CONSTRAINT ck_banana_order_status CHECK (status IN ('DRAFT', 'RESERVED', 'PAID', 'PICKING', 'SHIPPED', 'CANCELLED')),
    CONSTRAINT ck_banana_order_amounts CHECK (
        subtotal_amount >= 0 AND discount_amount >= 0 AND tax_amount >= 0 AND total_amount >= 0
    ),
    CONSTRAINT ck_banana_order_channel CHECK (source_channel IN ('WEB', 'MOBILE', 'EDI', 'CALL_CENTRE'))
)
PARTITION BY RANGE (order_date) INTERVAL (NUMTOYMINTERVAL(1, 'MONTH')) (
    PARTITION banana_orders_before_2026 VALUES LESS THAN (DATE '2026-01-01')
);

CREATE TABLE banana_order_lines (
    order_line_id     NUMBER(14)       NOT NULL,
    order_id          NUMBER(14)       NOT NULL,
    line_number       NUMBER(6)        NOT NULL,
    product_id        NUMBER(12)       NOT NULL,
    warehouse_id      NUMBER(12)       NOT NULL,
    quantity          NUMBER(10)       NOT NULL,
    unit_price        NUMBER(12,2)     NOT NULL,
    discount_percent  NUMBER(5,2)      DEFAULT 0 NOT NULL,
    tax_rate          NUMBER(5,4)      DEFAULT 0 NOT NULL,
    line_total        NUMBER(15,2)     NOT NULL,
    fulfilment_status VARCHAR2(20 CHAR) DEFAULT 'PENDING' NOT NULL,
    CONSTRAINT pk_banana_order_lines PRIMARY KEY (order_line_id),
    CONSTRAINT uq_banana_order_line UNIQUE (order_id, line_number),
    CONSTRAINT fk_banana_line_order FOREIGN KEY (order_id)
        REFERENCES banana_orders (order_id),
    CONSTRAINT fk_banana_line_product FOREIGN KEY (product_id)
        REFERENCES banana_products (product_id),
    CONSTRAINT fk_banana_line_inventory FOREIGN KEY (warehouse_id, product_id)
        REFERENCES banana_inventory (warehouse_id, product_id),
    CONSTRAINT ck_banana_line_quantity CHECK (quantity > 0),
    CONSTRAINT ck_banana_line_discount CHECK (discount_percent BETWEEN 0 AND 100),
    CONSTRAINT ck_banana_line_tax CHECK (tax_rate BETWEEN 0 AND 1),
    CONSTRAINT ck_banana_line_status CHECK (fulfilment_status IN ('PENDING', 'RESERVED', 'PICKED', 'SHIPPED', 'CANCELLED'))
);

CREATE TABLE banana_payments (
    payment_id        NUMBER(14)       NOT NULL,
    order_id          NUMBER(14)       NOT NULL,
    provider_reference VARCHAR2(100 CHAR) NOT NULL,
    payment_method    VARCHAR2(20 CHAR) NOT NULL,
    amount            NUMBER(15,2)     NOT NULL,
    currency_code     CHAR(3 CHAR)     NOT NULL,
    status            VARCHAR2(20 CHAR) DEFAULT 'PENDING' NOT NULL,
    paid_at           TIMESTAMP(6) WITH TIME ZONE,
    metadata_json     CLOB,
    CONSTRAINT pk_banana_payments PRIMARY KEY (payment_id),
    CONSTRAINT uq_banana_payment_reference UNIQUE (provider_reference),
    CONSTRAINT fk_banana_payment_order FOREIGN KEY (order_id)
        REFERENCES banana_orders (order_id),
    CONSTRAINT ck_banana_payment_method CHECK (payment_method IN ('CARD', 'INVOICE', 'BANK_TRANSFER')),
    CONSTRAINT ck_banana_payment_amount CHECK (amount > 0),
    CONSTRAINT ck_banana_payment_status CHECK (status IN ('PENDING', 'AUTHORIZED', 'CAPTURED', 'FAILED', 'REFUNDED')),
    CONSTRAINT ck_banana_payment_json CHECK (metadata_json IS JSON)
);

CREATE TABLE banana_shipments (
    shipment_id       NUMBER(14)       NOT NULL,
    order_id          NUMBER(14)       NOT NULL,
    warehouse_id      NUMBER(12)       NOT NULL,
    carrier_code      VARCHAR2(30 CHAR) NOT NULL,
    tracking_number   VARCHAR2(100 CHAR),
    status            VARCHAR2(20 CHAR) DEFAULT 'CREATED' NOT NULL,
    shipped_at        TIMESTAMP(6) WITH TIME ZONE,
    delivered_at      TIMESTAMP(6) WITH TIME ZONE,
    CONSTRAINT pk_banana_shipments PRIMARY KEY (shipment_id),
    CONSTRAINT uq_banana_tracking UNIQUE (carrier_code, tracking_number),
    CONSTRAINT fk_banana_shipment_order FOREIGN KEY (order_id)
        REFERENCES banana_orders (order_id),
    CONSTRAINT fk_banana_shipment_warehouse FOREIGN KEY (warehouse_id)
        REFERENCES banana_warehouses (warehouse_id),
    CONSTRAINT ck_banana_shipment_status CHECK (status IN ('CREATED', 'PICKING', 'DISPATCHED', 'DELIVERED', 'CANCELLED')),
    CONSTRAINT ck_banana_shipment_dates CHECK (delivered_at IS NULL OR shipped_at IS NOT NULL)
);

CREATE TABLE banana_outbox_events (
    event_id          NUMBER(14)       NOT NULL,
    aggregate_type    VARCHAR2(50 CHAR) NOT NULL,
    aggregate_id      VARCHAR2(100 CHAR) NOT NULL,
    event_type        VARCHAR2(100 CHAR) NOT NULL,
    payload_json      CLOB             NOT NULL,
    correlation_id    VARCHAR2(64 CHAR),
    occurred_at       TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    published_at      TIMESTAMP(6) WITH TIME ZONE,
    publish_attempts  NUMBER(6)        DEFAULT 0 NOT NULL,
    CONSTRAINT pk_banana_outbox_events PRIMARY KEY (event_id),
    CONSTRAINT ck_banana_outbox_json CHECK (payload_json IS JSON),
    CONSTRAINT ck_banana_publish_attempts CHECK (publish_attempts >= 0)
);

CREATE TABLE banana_order_audit (
    audit_id          NUMBER(14)       NOT NULL,
    order_id          NUMBER(14)       NOT NULL,
    changed_at        TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    changed_by        VARCHAR2(128 CHAR) DEFAULT SYS_CONTEXT('USERENV', 'SESSION_USER') NOT NULL,
    old_status        VARCHAR2(20 CHAR),
    new_status        VARCHAR2(20 CHAR),
    old_total_amount  NUMBER(15,2),
    new_total_amount  NUMBER(15,2),
    change_reason     VARCHAR2(500 CHAR),
    CONSTRAINT pk_banana_order_audit PRIMARY KEY (audit_id),
    CONSTRAINT fk_banana_audit_order FOREIGN KEY (order_id)
        REFERENCES banana_orders (order_id)
);

CREATE INDEX ix_banana_address_customer ON banana_addresses (customer_id, address_type);
CREATE INDEX ix_banana_product_category ON banana_products (category, status);
CREATE INDEX ix_banana_inventory_product ON banana_inventory (product_id, warehouse_id);
CREATE INDEX ix_banana_order_customer_date ON banana_orders (customer_id, order_date) LOCAL;
CREATE INDEX ix_banana_order_status_date ON banana_orders (status, order_date) LOCAL;
CREATE INDEX ix_banana_line_order ON banana_order_lines (order_id);
CREATE INDEX ix_banana_payment_order ON banana_payments (order_id, status);
CREATE INDEX ix_banana_shipment_order ON banana_shipments (order_id, status);
CREATE INDEX ix_banana_outbox_pending ON banana_outbox_events (published_at, occurred_at);
CREATE INDEX ix_banana_audit_order ON banana_order_audit (order_id, changed_at);

PROMPT Banana Commerce schema created.