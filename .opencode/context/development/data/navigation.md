<!-- Context: development/navigation | Priority: critical | Version: 1.0 | Updated: 2026-02-15 -->

# Data Layer Navigation

**Purpose**: Database and data access patterns

**Status**: ✅ Active - PostgreSQL patterns documented

---

## Planned Structure

```
data/
├── navigation.md
│
├── aspa/
│   └── aspa-schema.md          ✅ Active - aspadb schema reference
│
├── sql-patterns/
│   ├── postgres-patterns.md   ✅ Active
│   ├── mysql-patterns.md      (planned)
│   └── query-optimization.md  (planned)
│
├── nosql-patterns/
│   ├── mongodb-patterns.md
│   ├── redis-patterns.md
│   └── dynamodb-patterns.md
│
└── orm-patterns/
    ├── prisma-patterns.md
    ├── typeorm-patterns.md
    └── sequelize-patterns.md
```

---

## Related Context

- **Backend Navigation** → `../backend-navigation.md`
- **Core Standards** → `../../core/standards/code-quality.md`
