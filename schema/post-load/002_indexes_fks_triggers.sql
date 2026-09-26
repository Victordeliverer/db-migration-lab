-- Applied AFTER full load on the target (and right after seeding on the source).
CREATE UNIQUE INDEX IF NOT EXISTS ux_customers_email ON customers (email);
CREATE UNIQUE INDEX IF NOT EXISTS ux_products_sku ON products (sku);
CREATE INDEX IF NOT EXISTS ix_addresses_customer ON addresses (customer_id);
CREATE INDEX IF NOT EXISTS ix_products_category ON products (category_id);
CREATE INDEX IF NOT EXISTS ix_orders_customer ON orders (customer_id);
CREATE INDEX IF NOT EXISTS ix_orders_created ON orders (created_at);
CREATE INDEX IF NOT EXISTS ix_order_items_order ON order_items (order_id);
CREATE INDEX IF NOT EXISTS ix_order_items_product ON order_items (product_id);
CREATE INDEX IF NOT EXISTS ix_payments_order ON payments (order_id);
CREATE INDEX IF NOT EXISTS ix_docs_product ON product_documents (product_id);

ALTER TABLE addresses ADD CONSTRAINT fk_addr_customer FOREIGN KEY (customer_id) REFERENCES customers (customer_id);
ALTER TABLE products ADD CONSTRAINT fk_prod_category FOREIGN KEY (category_id) REFERENCES categories (category_id);
ALTER TABLE orders ADD CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id) REFERENCES customers (customer_id);
ALTER TABLE orders ADD CONSTRAINT fk_orders_address FOREIGN KEY (address_id) REFERENCES addresses (address_id);
ALTER TABLE order_items ADD CONSTRAINT fk_items_order FOREIGN KEY (order_id) REFERENCES orders (order_id);
ALTER TABLE order_items ADD CONSTRAINT fk_items_product FOREIGN KEY (product_id) REFERENCES products (product_id);
ALTER TABLE payments ADD CONSTRAINT fk_pay_order FOREIGN KEY (order_id) REFERENCES orders (order_id);
ALTER TABLE product_documents ADD CONSTRAINT fk_docs_product FOREIGN KEY (product_id) REFERENCES products (product_id);

CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_orders_updated ON orders;
CREATE TRIGGER trg_orders_updated BEFORE UPDATE ON orders
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE VIEW v_order_summary AS
  SELECT o.order_id, o.customer_id, o.status, o.total_amount, count(i.order_item_id) AS items
  FROM orders o LEFT JOIN order_items i USING (order_id)
  GROUP BY o.order_id;
