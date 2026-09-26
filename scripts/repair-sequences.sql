-- Run on the TARGET before opening writes. DMS does not carry sequence values.
SELECT setval(pg_get_serial_sequence('customers','customer_id'),          COALESCE((SELECT max(customer_id) FROM customers),1));
SELECT setval(pg_get_serial_sequence('addresses','address_id'),           COALESCE((SELECT max(address_id) FROM addresses),1));
SELECT setval(pg_get_serial_sequence('categories','category_id'),         COALESCE((SELECT max(category_id) FROM categories),1));
SELECT setval(pg_get_serial_sequence('products','product_id'),            COALESCE((SELECT max(product_id) FROM products),1));
SELECT setval(pg_get_serial_sequence('orders','order_id'),                COALESCE((SELECT max(order_id) FROM orders),1));
SELECT setval(pg_get_serial_sequence('order_items','order_item_id'),      COALESCE((SELECT max(order_item_id) FROM order_items),1));
SELECT setval(pg_get_serial_sequence('payments','payment_id'),            COALESCE((SELECT max(payment_id) FROM payments),1));
SELECT setval(pg_get_serial_sequence('product_documents','document_id'),  COALESCE((SELECT max(document_id) FROM product_documents),1));
