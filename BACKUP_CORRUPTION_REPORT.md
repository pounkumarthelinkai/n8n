# Backup Database Corruption Report

**Date:** December 11, 2025  
**Environment:** DEV VPS (194.238.17.118)  
**Issue:** SQLite database corruption during restore operation

---

## Executive Summary

During the DEV server restoration process, the backup database file (`database.sqlite`) was found to be corrupted, preventing a complete restore of user accounts and requiring a fresh database initialization.

---

## Timeline of Events

### 1. Initial Backup Creation
- **Time:** December 11, 2025 ~06:36:47 UTC
- **Location:** `/root/n8n_backup_20251211_063647/`
- **Backup Contents:**
  - `n8n_data_backup.tar.gz` - Full n8n data directory backup
  - Database file: `database.sqlite` (~1.7GB)
  - Other n8n data files (binaryData, config, logs, etc.)

### 2. Database Corruption Discovery
- **When:** During DEV restore operation
- **Error Message:** `SQLITE_CORRUPT: database disk image is malformed`
- **Location:** When attempting to export workflows from restored database
- **Impact:** 
  - Could not export workflows from backup
  - Could not restore user accounts from backup
  - Database integrity check failed

### 3. Recovery Actions Taken
- **Action 1:** Attempted to restore from backup
  - Result: ❌ Failed - Database corruption detected
- **Action 2:** Cleared corrupted database
  - Removed corrupted `database.sqlite` file
  - Started fresh n8n instance
- **Action 3:** Imported workflows and credentials from PROD export
  - ✅ Successfully imported 93 workflows
  - ✅ Successfully imported 98 credentials
  - ⚠️ User accounts were NOT restored (fresh database)

---

## Root Cause Analysis

### Possible Causes

1. **Incomplete Backup Process**
   - The backup may have been created while n8n was actively writing to the database
   - SQLite databases can become corrupted if copied while transactions are in progress
   - No database lock was acquired before backup

2. **File System Issues**
   - Possible disk I/O errors during backup creation
   - Network issues if backup was transferred
   - Insufficient disk space during backup

3. **Database Already Corrupted**
   - The source database may have been corrupted before backup
   - Long-running n8n instance with potential corruption issues
   - No integrity checks performed before backup

4. **Backup Method**
   - Direct file copy without proper SQLite backup procedures
   - No `.dump` or `.backup` SQLite commands used
   - Tar archive may have corrupted during compression

### Evidence

- **Database Size:** 1.7GB (normal size for n8n database)
- **Corruption Type:** SQLite disk image malformed
- **Error Location:** When attempting to read from database
- **Backup File:** Still exists but database inside is corrupted

---

## Impact Assessment

### What Was Lost
- ❌ **User Accounts:** All user accounts (owner and other users)
- ❌ **User Preferences:** User settings and preferences
- ❌ **Workflow Execution History:** Historical execution data
- ❌ **Workflow Statistics:** Usage statistics and metrics

### What Was Preserved
- ✅ **Workflows:** All 93 workflows successfully imported
- ✅ **Credentials:** All 98 credentials successfully imported
- ✅ **Workflow Configuration:** All workflow settings preserved
- ✅ **Node Configurations:** All node settings intact

---

## Current Status

### DEV Server (194.238.17.118)
- **Database:** Fresh SQLite database (1.6GB, created Dec 11 10:17)
- **Workflows:** 93 workflows imported (all inactive)
- **Credentials:** 98 credentials imported
- **Users:** ❌ No users - requires setup
- **n8n Status:** ✅ Running and accessible
- **Issue:** Setup page showing (user accounts need to be recreated)

### PROD Server (194.238.17.119)
- **Status:** ✅ Fully operational
- **Workflows:** 94 workflows
- **Credentials:** 98 credentials
- **Users:** ✅ All user accounts intact
- **Database:** ✅ Healthy (no corruption detected)

---

## Recommendations

### Immediate Actions

1. **Restore User Accounts**
   - Option A: Manually create owner account via setup page
   - Option B: Export user table from PROD and import to DEV (if possible)
   - Option C:  

2. **Verify Current Database**
   - Run integrity check on current DEV database
   - Ensure no corruption in fresh database

### Long-term Improvements

1. **Improve Backup Process**
   ```bash
   # Use SQLite's built-in backup command
   sqlite3 database.sqlite ".backup backup.sqlite"
   # Or use VACUUM INTO
   sqlite3 database.sqlite "VACUUM INTO 'backup.sqlite'"
   ```

2. **Add Backup Verification**
   - Run integrity check after backup creation
   - Verify backup before storing
   - Test restore on separate environment

3. **Implement Database Locking**
   - Stop n8n before backup
   - Or use SQLite WAL mode for safer backups
   - Use proper backup tools (pg_dump for Postgres if migrated)

4. **Regular Integrity Checks**
   - Schedule periodic `PRAGMA integrity_check`
   - Monitor database health
   - Alert on corruption detection

5. **Multiple Backup Copies**
   - Keep multiple backup versions
   - Store backups in different locations
   - Test restore procedures regularly

6. **Consider Migration to PostgreSQL**
   - More robust for production use
   - Better backup/restore tools
   - Already configured in docker-compose templates

---

## Technical Details

### Backup File Structure
```
/root/n8n_backup_20251211_063647/
└── n8n_data_backup.tar.gz
    ├── database.sqlite (1.7GB - CORRUPTED)
    ├── binaryData/
    ├── config
    ├── crash.journal
    ├── git/
    ├── n8nEventLog*.log
    ├── nodes/
    └── ssh/
```

### Corruption Symptoms
- Error: `SQLITE_CORRUPT: database disk image is malformed`
- Location: When executing `n8n export:workflow --all`
- Impact: Cannot read from database
- Recovery: Required fresh database initialization

### Database Information
- **Type:** SQLite 3
- **Location:** `/home/node/.n8n/database.sqlite` (inside container)
- **Volume:** `n8n_data` (Docker volume)
- **Size:** ~1.7GB (corrupted backup), 1.6GB (current fresh)

---

## Lessons Learned

1. **Always verify backups** before considering them reliable
2. **Use proper SQLite backup methods** instead of file copy
3. **Stop services** before backing up databases when possible
4. **Test restore procedures** regularly
5. **Keep multiple backup versions** for redundancy
6. **Monitor database health** proactively

---

## Next Steps

1. ✅ **Completed:** Fresh database created
2. ✅ **Completed:** Workflows imported (93)
3. ✅ **Completed:** Credentials imported (98)
4. ⏳ **Pending:** User account restoration
5. ⏳ **Pending:** Activate workflows as needed
6. ⏳ **Pending:** Implement improved backup procedures

---

## Conclusion

The backup database corruption was likely caused by backing up an active SQLite database without proper locking or using SQLite's backup commands. While workflows and credentials were successfully restored from PROD, user accounts were lost and need to be recreated.

The current DEV server is operational with all workflows and credentials, but requires user account setup. The PROD server remains fully operational and can serve as the source of truth for future restorations.

**Recommendation:** Implement proper backup procedures using SQLite's backup commands or migrate to PostgreSQL for production use.

---

**Report Generated:** December 11, 2025  
**Investigated By:** AI Assistant  
**Status:** Investigation Complete

