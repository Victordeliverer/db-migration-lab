-- Base schema: extensions, types, tables + primary keys ONLY.
-- Indexes, foreign keys and triggers live in schema/post-load/ so they do not
-- block DMS full load (DMS loads table-by-table, so active FKs cause failures).
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

DO $$ BEGIN
  CREATE TYPE order_status AS ENUM ('pending','paid','shipped','delivered','cancelled','refunded');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS customers (
  customer_id  BIGSERIAL PRIMARY KEY,
  email        TEXT NOT NULL,
  full_name    TEXT NOT NULL,
  tags         TEXT[],                         -- array type risk
  notes        TEXT,                           -- large text (LOB) risk
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS addresses (
  address_id   BIGSERIAL PRIMARY KEY,
  customer_id  BIGINT NOT NULL,
  line1        TEXT NOT NULL,
  city         TEXT NOT NULL,
  postal_code  TEXT,
  country      CHAR(2) NOT NULL
);

CREATE TABLE IF NOT EXISTS categories (
  category_id  BIGSERIAL PRIMARY KEY,
  name         TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS products (
  product_id   BIGSERIAL PRIMARY KEY,
  category_id  BIGINT NOT NULL,
  sku          TEXT NOT NULL,
  name         TEXT NOT NULL,
  price        NUMERIC(12,2) NOT NULL,
  attributes   JSONB,                          -- JSONB risk
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS orders (
  order_id      BIGSERIAL PRIMARY KEY,
  customer_id   BIGINT NOT NULL,
  address_id    BIGINT NOT NULL,
  status        order_status NOT NULL DEFAULT 'pending',   -- enum risk
  total_amount  NUMERIC,                                   -- unconstrained NUMERIC risk
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS order_items (
  order_item_id BIGSERIAL PRIMARY KEY,
  order_id      BIGINT NOT NULL,
  product_id    BIGINT NOT NULL,
  quantity      INT NOT NULL,
  unit_price    NUMERIC(12,2) NOT NULL
);

CREATE TABLE IF NOT EXISTS payments (
  payment_id    BIGSERIAL PRIMARY KEY,
  order_id      BIGINT NOT NULL,
  amount        NUMERIC(14,2) NOT NULL,
  method        TEXT NOT NULL,
  paid_at       TIMESTAMPTZ NOT NULL               -- time zone risk
);

CREATE TABLE IF NOT EXISTS product_documents (
  document_id   BIGSERIAL PRIMARY KEY,
  product_id    BIGINT NOT NULL,
  filename      TEXT NOT NULL,
  file_data     BYTEA NOT NULL                     -- bytea LOB risk
);

-- Deliberately NO primary key: the "table without a PK" test case.
CREATE TABLE IF NOT EXISTS audit_log (
  event_time    TIMESTAMPTZ NOT NULL DEFAULT now(),
  actor         TEXT NOT NULL,
  action        TEXT NOT NULL,
  detail        TEXT
);
