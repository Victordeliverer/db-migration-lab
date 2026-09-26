# Discovery and Compatibility: PostgreSQL 15 (EC2) to Aurora PostgreSQL 15 (eu-west-1)

> **Status:** Draft v2 (pre-Day 1) | **Owner:** Victor | **Last updated:** 2026-09-24
> **Environment:** Lab, synthetic data only | **Region:** eu-west-1 (Ireland)
> **Expiry tag:** set to lab end date, e.g. 2026-10-15 (update if you extend)

**How to use this file:** Values are filled in from the decisions made so far. Anything
marked **[TBD-D2]** gets confirmed after Day 2 (once the source DB is seeded and
`inventory.sql` has run). Anything marked **[VERIFY]** must be checked against AWS
before you rely on it. Lines marked **Why it matters** are for learning and interview
answers, so keep them and rewrite them in your own words as you learn.

---

## 1. Migration summary

| Item | Value |
|---|---|
| Source | PostgreSQL 15 on EC2 (self-managed, simulates a legacy database) |
| Target | Aurora PostgreSQL 15.19 in eu-west-1 (pin exact minor after the CLI check in section 2.1) |
| Migration engine | AWS DMS, one `full-load-and-cdc` task |
| Region | eu-west-1 (Ireland) |
| Approx. data volume | 500k rows, ~1.5 GB |
| Migration type | Homogeneous (PostgreSQL to PostgreSQL) |
| Downtime approach | Short, controlled write pause at cutover (not zero-downtime) |
| Major version path | 15 to 15 (major upgrade deliberately deferred, see section 7) |

**Why it matters:** Homogeneous migrations avoid schema-conversion tools, but they do
not remove type, extension, sequence, or DDL edge cases. Keeping the major version the
same means any difference you see comes from the migration, not from an upgrade.

---

## 2. Engine and environment compatibility

| Property | Source | Target | Compatible? | Notes |
|---|---|---|---|---|
| Major version | 15.x | 15.x | Yes | Same major on purpose |
| Encoding | UTF8 | UTF8 | Yes | Must match, or text can corrupt |
| Collation / locale | `en_US.UTF-8` | `en_US.UTF-8` | [VERIFY] | Set explicitly on both sides; mismatches change index ordering and uniqueness |
| Time zone | UTC | UTC | Yes | Use `timestamptz` for timestamps |
| Extensions | `pgcrypto`, `uuid-ossp` (planned) | same | [VERIFY] | Confirm each is supported on Aurora PG 15 before building schema |
| Logical decoding plugin | `test_decoding` (lab choice) | n/a | [TBD-D2] | Confirm against current DMS docs on Day 2; record the plugin in evidence |
| `wal_level` | `logical` | n/a | n/a | Needs a source restart to change |
| `max_replication_slots` / `max_wal_senders` | set above the minimum (e.g. 10) | n/a | [TBD-D2] | Leave headroom for retries and restarts |

### 2.1 Pin the Aurora version (run before Day 3)

```bash
aws rds describe-db-engine-versions \
  --engine aurora-postgresql \
  --engine-version 15 \
  --region eu-west-1 \
  --query 'DBEngineVersions[].EngineVersion' \
  --output text
```

Record the highest 15.19 returned: **Aurora engine version: `15.19` [VERIFY]**.
Aurora 15.17 was announced in April 2026, so expect something at or near that.

Also record: **DMS replication engine version:** choose the latest available when you
create the replication instance (the default is not always the newest).

**Why it matters:** Regional availability of a minor version can lag the global
announcement. Pinning the version in Terraform stops plans from drifting.

---

## 3. Table inventory (planned, approximate)

Row counts sum to ~500k. Adjust in `scripts/seed.py`; update this table to match what
you actually seed and what `inventory.sql` reports.

| # | Schema.Table | Approx. rows | Primary key | Write rate | Depends on (FKs) | Criticality | In scope? |
|---|---|---|---|---|---|---|---|
| 1 | `public.customers` | 20,000 | `customer_id` | Low | none | High | Yes |
| 2 | `public.addresses` | 25,000 | `address_id` | Low | `customers` | Medium | Yes |
| 3 | `public.categories` | 50 | `category_id` | Very low | none | Low | Yes |
| 4 | `public.products` | 5,000 | `product_id` | Low | `categories` | Medium | Yes |
| 5 | `public.orders` | 100,000 | `order_id` | High | `customers`, `addresses` | High | Yes |
| 6 | `public.order_items` | 229,000 | `order_item_id` | High | `orders`, `products` | High | Yes |
| 7 | `public.payments` | 100,000 | `payment_id` | Medium | `orders` | High | Yes |
| 8 | `public.product_documents` | 1,000 | `document_id` | Very low | `products` | Low | Yes (LOB test) |
| 9 | `public.audit_log` | 20,000 | **none** | High | none | Low | **Exception (section 3.1)** |

Total: ~500,050 rows. Estimated size ~1.5 GB [TBD-D2].

### 3.1 Tables without a primary key

| Table | Decision | Reason |
|---|---|---|
| `public.audit_log` | Decide on Day 2: (a) add a surrogate PK, or (b) keep as a controlled test case | Deliberately kept to prove the "no PK" risk. Test UPDATE/DELETE behavior under CDC and record the result in `docs/evidence/`. |

**Why it matters:** DMS can ignore `UPDATE` and `DELETE` on tables with no primary key,
so the task looks healthy while the target drifts. This is the most important
eligibility rule in the project. Every table needs a PK or an approved, tested exception.

---

## 4. Data type risk register

Create representative test rows for each (in `scripts/seed.py`).

| Column | Type | Risk | Test planned | Decision / setting |
|---|---|---|---|---|
| `orders.total_amount` | `NUMERIC` (no precision) | Precision/scale handling | Insert values with 20+ digits and many decimals | [TBD-D4] |
| `products.attributes` | `JSONB` | Handled as LOB; content equality | Nested JSON, empty `{}`, NULL | [TBD-D4] |
| `customers.tags` | `TEXT[]` | Array handling | Empty array, NULL, multi-element | [TBD-D4] |
| `orders.status` | `ENUM` (`order_status`) | Custom type must exist on target first | Create type in `schema/pre-load/` | Deploy in base schema |
| `customers.notes` | `TEXT` (large) | LOB mode and truncation | Rows above the LOB size limit | [TBD-D4] (Limited vs Full LOB, size in KB) |
| `product_documents.file_data` | `BYTEA` | LOB handling | Rows of small, medium, large sizes | [TBD-D4] |
| `payments.paid_at` | `TIMESTAMPTZ` | Time zone handling | Values across DST boundaries | Compare in UTC |

**Why it matters:** *Limited LOB* mode is faster but truncates values above the limit.
*Full LOB* is safe but slower. Choose deliberately, test with realistically sized rows,
and record any acceptable lossiness.

---

## 5. Database objects

| Object type | Present in source? | Migrated by DMS? | Handled how |
|---|---|---|---|
| Schemas | Yes | No | `schema/pre-load/` |
| Table structure | Yes | Partly | `schema/pre-load/` (do not let DMS create tables) |
| Primary keys | Yes | With table | Included in pre-load |
| Secondary indexes | Yes | No | `schema/post-load/` |
| Foreign keys | Yes | No | `schema/post-load/`, applied after full load |
| Triggers | Yes (1 simple `updated_at` trigger, planned) | No | `schema/post-load/` |
| Functions / procedures | Minimal | No | Deploy manually and test |
| Views / materialized views | 1 view (planned) | No | Deploy manually |
| Sequences | Yes (one per PK) | Values not carried | `scripts/repair-sequences.sql` before opening writes |
| Roles and grants | `app_user`, `dms_user` | No | Recreate on target, least privilege |
| Row-level security | No | n/a | Out of scope for lab |
| Scheduled jobs (pg_cron etc.) | No | n/a | Out of scope for lab |

**Why it matters:** DMS moves data, not the whole database. Sequences are the classic
gotcha: the target sequence stays at its start value, so the first insert after cutover
fails with a duplicate key error. Repair sequences before opening writes.

---

## 6. Workload, capacity, and sizing

| Metric | Value | Notes |
|---|---|---|
| Database size | ~1.5 GB [TBD-D2] | `SELECT pg_size_pretty(pg_database_size(current_database()));` |
| Peak write rate | [TBD-D5] (e.g. 50 tx/s from `workload.py`) | Record what you actually generate |
| Longest transaction | [TBD-D5] | Long transactions delay WAL release |
| Largest transaction | [TBD-D5] | |
| Source instance | e.g. `t3.large`, encrypted gp3 volume (~50 GB) | Leave large headroom for retained WAL |
| Source disk free at start | [TBD-D2] | |
| WAL / disk alert threshold | e.g. warn at 60% disk used | Tune from measured baseline |
| DMS replication instance | e.g. `dms.t3.medium` | Right-size from measured load |
| Aurora instance | e.g. `db.t4g.medium` [VERIFY] | Lab-sized; production sizing differs |
| Aurora reader | None in lab (stretch: reader in a second AZ) | Availability tradeoff, see design doc |

**Why it matters:** A stalled logical replication slot retains WAL and can fill the
source disk, taking the source database down. This is the biggest operational risk of
CDC, which is why you alarm on slot lag and free disk.

---

## 7. Migration rules and design decisions

| Rule / decision | Value |
|---|---|
| DDL during CDC | Frozen (lab). Production: expand/contract on both sides |
| Primary-key changes | Prohibited during CDC |
| `TRUNCATE` / partition operations | Prohibited during the migration window |
| Long transactions | Break into small transactions |
| DMS tasks | One task (single transactional boundary) |
| Target table preparation | Do nothing / truncate only; never drop (protects pre-load schema) |
| Major version upgrade | Deferred: a separate project after cutover (e.g. blue/green) |
| Foreign keys and triggers | Created in post-load stage after full load |

---

## 8. Objectives and ownership

| Item | Value |
|---|---|
| RPO (max tolerated data loss) | 0 committed transactions lost |
| RTO (max tolerated outage) | 30 minutes end to end |
| Write-pause target | Under 60 seconds (derive the real number from measured CDC lag) |
| CDC lag threshold for cutover | Under 5 seconds, sustained for 10 minutes |
| Maintenance window | [TBD-D7] date, start time, end time, time zone (Europe/Lisbon or UTC) |
| Migration lead | Victor |
| Application owner | Victor (lab) |
| Database owner | Victor (lab) |
| Decision maker (cutover and rollback) | Victor (lab) |

**Why it matters:** Every later decision (alarm thresholds, write-pause length, rollback
rules) is measured against RPO and RTO. Tune these numbers from your measured baseline
and update this table; do not leave placeholders standing.

---

## 9. Cost and tagging

| Item | Value |
|---|---|
| Default tags | `project=db-migration-lab`, `owner=victor`, `environment=lab`, `expiry=<date>` |
| Budget alert | Set before first apply; thresholds at 50%, 80%, 100% |
| Pricing estimate | Record the AWS Pricing Calculator estimate for eu-west-1 here [TBD-D1] |
| Main cost drivers | Aurora instance hours, DMS instance hours, NAT gateway (avoid), interface endpoints, CloudWatch logs, cross-AZ traffic |
| Rule | Deploy only during active sessions; tear down after each major stage if practical |

---

## 10. Risks and open questions

| # | Risk / question | Impact | Mitigation | Status |
|---|---|---|---|---|
| 1 | Table without PK loses UPDATE/DELETE in CDC | Silent data drift | Add PK or test and document exception | Open |
| 2 | Retained WAL fills source disk | Source outage | Slot and disk alarms, small transactions | Open |
| 3 | Extension not supported on Aurora PG 15 | Schema deploy fails | Verify list in section 2 before Day 3 | Open |
| 4 | Sequence not repaired at cutover | Duplicate key errors | Repair script in runbook | Open |
| 5 | Aurora minor version differs in eu-west-1 | Terraform apply fails | CLI check in section 2.1 | Open |
| 6 | LOB settings truncate data | Silent data loss | Test representative rows, choose mode deliberately | Open |
| 7 | Cost overrun from idle resources | Surprise bill | Budget alert, expiry tags, teardown script | Open |

---

## 11. Sign-off checklist

| Check | Done? |
|---|---|
| Every in-scope table has a PK or an approved exception | [ ] |
| Type risk register complete, test rows planned | [ ] |
| Extension and collation compatibility verified | [ ] |
| Aurora minor version pinned (CLI check run) | [ ] |
| RPO, RTO, lag threshold, and roles written down | [ ] |
| Budget alert and default tags planned | [ ] |
| Ready to proceed to Day 1 | [ ] |

---

## Evidence to attach as you go (`docs/evidence/`)

- Day 2: `inventory.sql` output, replication settings, plugin used, source free space
- Day 3: schema comparison showing only approved differences
- Day 4: full-load throughput and validation results
- Day 5: CDC lag under load, task restart recovery notes
- Day 6: dashboard screenshot, alarm test, recovery exercise results
- Day 7: cutover timeline with timestamps and validation output