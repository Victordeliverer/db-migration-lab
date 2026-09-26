#!/usr/bin/env python3
"""Seed synthetic data for the migration lab. Synthetic data only.

Order: schema (pre-load) -> COPY data -> constraints (post-load), so the source
ends up with real foreign keys, like a legacy database.

Usage:
  export PGHOST=... PGPORT=5432 PGDATABASE=appdb PGUSER=app_owner PGSSLMODE=require
  # password via PGPASSWORD or ~/.pgpass (never paste it into shell history)
  python scripts/seed.py --scale 1.0      # ~500k rows, ~1.3-1.5 GB (large bytea LOBs up to 3 MB)
  python scripts/seed.py --scale 0.02     # quick smoke test
"""
import argparse, io, json, os, random, sys, time
from pathlib import Path
import psycopg2
from faker import Faker

ROOT = Path(__file__).resolve().parent.parent

def esc(v):
    if v is None:
        return r"\N"
    return str(v).replace("\\", "\\\\").replace("\t", " ").replace("\n", "\\n").replace("\r", " ")

def copy(cur, table, cols, rows):
    buf = io.StringIO()
    for r in rows:
        buf.write("\t".join(r) + "\n")
    buf.seek(0)
    cur.copy_expert(f"COPY {table} ({','.join(cols)}) FROM STDIN", buf)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scale", type=float, default=1.0, help="1.0 = ~500k rows")
    ap.add_argument("--seed", type=int, default=42)
    a = ap.parse_args()
    random.seed(a.seed); Faker.seed(a.seed); fk = Faker()
    n = lambda base: max(1, int(base * a.scale))
    N = dict(cust=n(20000), addr=n(25000), cat=50 if a.scale >= 0.1 else 5, prod=n(5000),
             ord=n(100000), items=n(229000), pay=n(100000), docs=n(1000), audit=n(20000))

    conn = psycopg2.connect(connect_timeout=15)   # uses PG* env vars
    cur = conn.cursor()
    t0 = time.time()
    cur.execute((ROOT / "schema/pre-load/001_base_schema.sql").read_text())
    cur.execute("SELECT count(*) FROM customers")
    if cur.fetchone()[0] > 0:
        sys.exit("customers is not empty; refusing to seed twice. Recreate the DB first.")

    copy(cur, "categories", ["category_id", "name"],
         [(str(i), esc(f"{fk.word().title()} {i}")) for i in range(1, N["cat"] + 1)])

    rows = []
    for i in range(1, N["cust"] + 1):
        tags = random.choice([None, "{}", "{vip}", "{vip,newsletter}", '{"has space",promo}'])
        notes = fk.text(random.randint(2000, 18000)) if random.random() < 0.6 else None
        rows.append((str(i), esc(f"user{i}@example.test"), esc(fk.name()), esc(tags), esc(notes)))
    copy(cur, "customers", ["customer_id", "email", "full_name", "tags", "notes"], rows)

    cust_of_addr, rows = {}, []
    for i in range(1, N["addr"] + 1):
        c = i if i <= N["cust"] else random.randint(1, N["cust"])
        cust_of_addr[i] = c
        rows.append((str(i), str(c), esc(fk.street_address()), esc(fk.city()),
                     esc(fk.postcode()), random.choice(["PT", "IE", "ES", "FR", "DE", "NG"])))
    copy(cur, "addresses", ["address_id", "customer_id", "line1", "city", "postal_code", "country"], rows)

    rows = []
    for i in range(1, N["prod"] + 1):
        attrs = random.choice([None, "{}", json.dumps({"color": fk.color_name(),
                "dims": {"w": random.randint(1, 90), "h": random.randint(1, 90)}, "tags": [fk.word(), fk.word()]})])
        rows.append((str(i), str(random.randint(1, N["cat"])), esc(f"SKU-{i:07d}"), esc(fk.catch_phrase()),
                     f"{random.uniform(1, 900):.2f}", esc(attrs)))
    copy(cur, "products", ["product_id", "category_id", "sku", "name", "price", "attributes"], rows)

    statuses = ["pending", "paid", "shipped", "delivered", "cancelled", "refunded"]
    addr_ids, rows = list(cust_of_addr), []
    for i in range(1, N["ord"] + 1):
        ad = random.choice(addr_ids)
        total = random.choice([f"{random.uniform(1, 5000):.2f}", f"{random.uniform(1, 5000):.10f}",
                               "12345678901234567890.123456789", "0"])
        rows.append((str(i), str(cust_of_addr[ad]), str(ad), random.choice(statuses), total,
                     fk.date_time_between("-2y", "now").strftime("%Y-%m-%d %H:%M:%S+00")))
    copy(cur, "orders", ["order_id", "customer_id", "address_id", "status", "total_amount", "created_at"], rows)

    copy(cur, "order_items", ["order_item_id", "order_id", "product_id", "quantity", "unit_price"],
         [(str(i), str(random.randint(1, N["ord"])), str(random.randint(1, N["prod"])),
           str(random.randint(1, 9)), f"{random.uniform(1, 900):.2f}") for i in range(1, N["items"] + 1)])

    copy(cur, "payments", ["payment_id", "order_id", "amount", "method", "paid_at"],
         [(str(i), str(random.randint(1, N["ord"])), f"{random.uniform(1, 5000):.2f}",
           random.choice(["card", "paypal", "mbway", "transfer"]),
           fk.date_time_between("-2y", "now").strftime("%Y-%m-%d %H:%M:%S+00")) for i in range(1, N["pay"] + 1)])

    buf = io.StringIO()   # bytea LOBs of mixed size: small / medium / large
    for i in range(1, N["docs"] + 1):
        size = random.choice([2_000, 100_000, 600_000, 3_000_000])
        buf.write(f"{i}\t{random.randint(1, N['prod'])}\tdoc_{i}.bin\t\\\\x{os.urandom(size).hex()}\n")
    buf.seek(0)
    cur.copy_expert("COPY product_documents (document_id, product_id, filename, file_data) FROM STDIN", buf)

    copy(cur, "audit_log", ["actor", "action", "detail"],
         [(esc(random.choice(["admin", "app", "batch"])), esc(random.choice(["login", "update", "delete", "export"])),
           esc(fk.sentence())) for _ in range(N["audit"])])

    for tbl, col in [("customers", "customer_id"), ("addresses", "address_id"), ("categories", "category_id"),
                     ("products", "product_id"), ("orders", "order_id"), ("order_items", "order_item_id"),
                     ("payments", "payment_id"), ("product_documents", "document_id")]:
        cur.execute(f"SELECT setval(pg_get_serial_sequence('{tbl}','{col}'), (SELECT max({col}) FROM {tbl}))")
    cur.execute((ROOT / "schema/post-load/002_indexes_fks_triggers.sql").read_text())
    conn.commit()
    conn.autocommit = True
    cur.execute("ANALYZE")
    cur.execute("SELECT pg_size_pretty(pg_database_size(current_database()))")
    print("Rows:", N, "| DB size:", cur.fetchone()[0], f"| {time.time()-t0:.0f}s")

if __name__ == "__main__":
    main()
