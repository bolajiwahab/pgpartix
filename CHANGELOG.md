## 0.16.0 (2026-11-15)

### BREAKING CHANGE

- Container images now use Alpine instead of Debian.
Custom images and scripts may need package, command, or native
dependency changes.

### Feat

- switch PostgreSQL base images to Alpine (#143)

### Fix

- **deps**: update python updates (#136)
- keep the disposable cluster under the directory owned by PGP_OS_USER (#138)
- **deps**: update check-jsonschema, zensical (#126)
- **deps**: bump the python-packages group with 2 updates (#129)

### Refactor

- simplify PostgreSQL build stage names (#144)

## 0.15.0 (2026-10-04)

### Fix

- **deps**: update yq to 4.54.1 (#112)
- **deps**: bump the python-packages group with 3 updates (#115)
- **deps**: bump astral-sh/uv from 0.12.10 to 0.12.11 in the docker group (#105)

## 0.14.0 (2026-09-07)

### Fix

- ensure triggers are named when generate_partition_triggers is called directly (#101)
- process config directory in natural order (#99)

## 0.13.0 (2026-09-05)

### Fix

- handle root execution and migration file ordering (#98)
- **deps**: bump astral-sh/uv in the docker group across 1 directory (#95)

## 0.12.0 (2026-09-05)

### Fix

- **deps**: bump the python-packages group across 1 directory with 2 updates (#76)

### Refactor

- build PostgreSQL-specific image variants (#94)

## 0.11.0 (2026-08-15)

### Feat

- allow credentials to persistent for subsequent git calls (#70)
- tag latest docker image (#69)

## 0.10.0 (2026-08-15)

### Feat

- add mode for ephemeral cluster and external database (#68)

## 0.9.0 (2026-08-14)

### Feat

- more improvements (#63)

### Fix

- **deps**: bump check-jsonschema in the python-packages group (#62)

## 0.8.0 (2026-08-11)

### Fix

- generate output on formatter failures (#61)
- **deps**: bump check-jsonschema in the python-packages group (#60)
- bump pgrubic from 1.2.1 to 1.3.0 (#59)

## 0.7.1 (2026-08-10)

### Feat

- rename package (#56)

### Fix

- **deps**: bump python in the docker group (#58)

## 0.7.0 (2026-08-08)

### Feat

- rename project name to pgpartix (#55)
- rewrite (#51)

## 0.6.1 (2025-06-11)

## 0.6.0 (2025-06-11)

### Refactor

-  consistent typing (#31)

## 0.5.0 (2025-05-12)

### Feat

- rewrite concatenation into format (#27)
- allow skipping cluster creation in pg-start (#26)

### Refactor

- use quote with escape instead of dollar quoting (#29)

## 0.4.0 (2025-05-09)

### Feat

- update body when PR exists (#24)

### Fix

- future is relative to the current timestamp (#23)

## 0.3.0 (2025-05-09)

### Fix

- make-partitions start timestamp (#22)

## 0.2.0 (2025-05-09)

### Feat

- capture the partition maintenance in the body of PR, ensured required inputs for pgp-migrate (#21)

## 0.1.0 (2025-05-08)

### Feat

- remove migration tool from schemas, migration is managed independently (#19)
- add github cli (#13)
- pull request creation (#10)
- add support for flyway, goose, dbmate, go-migrate migration tools (#8)
- add support uuidv7
- generate migration file name from template, enable yamllint, provide config sample
- improve wrapper, move validation of existence of interval and name template to pg-generate-partitions
- add default for p_retention for expiration

### Fix

- remove relative paths (#18)
- schema.json does not exist (#17)
