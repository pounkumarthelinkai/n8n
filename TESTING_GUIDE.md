# Manual Workflow Testing Guide

## Step-by-Step Testing Instructions

### Step 1: Manually Trigger the Workflow

1. **Go to GitHub Repository**
   - Navigate to: https://github.com/pounkumarthelinkai/n8n

2. **Open Actions Tab**
   - Click on **"Actions"** in the top menu

3. **Select the Workflow**
   - Click on **"n8n CI/CD Pipeline"** in the left sidebar

4. **Run Workflow Manually**
   - Click the **"Run workflow"** button (top right, green button)
   - **Branch:** Select `main`
   - **Skip pre-deployment backup:** Leave unchecked (default: false)
   - Click **"Run workflow"** (green button)

### Step 2: Monitor Workflow Execution

1. **Watch the Workflow Run**
   - You'll see a new workflow run appear at the top
   - Click on it to see details

2. **Check Each Job**
   - **Export from DEV** - Should complete successfully
   - **Promote to Production** - Should run automatically after export
   - **Validate Workflows** - Should validate JSON files

3. **View Logs**
   - Click on each job to see detailed logs
   - Check for any errors or warnings

### Step 3: Verify Results

#### Check DEV Export
```bash
ssh -i C:\Users\admin\.ssh\github_deploy_key root@194.238.17.118
ls -lh /srv/n8n/migration-temp/export/
cat /srv/n8n/logs/export_*.log | tail -20
```

#### Check PROD Import
```bash
ssh -i C:\Users\admin\.ssh\github_deploy_key root@72.61.226.144
ls -lh /srv/n8n/migration-temp/import/
cat /srv/n8n/logs/import_*.log | tail -20
```

#### Check PROD Status
```bash
ssh -i C:\Users\admin\.ssh\github_deploy_key root@72.61.226.144
/srv/n8n/scripts/check_status.sh
```

### Step 4: Verify in n8n UI

1. **Check PROD n8n**
   - Open: https://n8n-prod.thelinkai.com
   - Verify workflows are present
   - Check that active workflows are activated

## Expected Workflow Steps

### Job 1: Export from DEV
- ✅ Checkout repository
- ✅ Setup SSH key
- ✅ Test SSH connection to DEV
- ✅ Run export script on DEV
- ✅ Download export artifacts
- ✅ Validate export artifacts
- ✅ Display export summary
- ✅ Upload export artifacts

### Job 2: Promote to Production
- ✅ Checkout repository
- ✅ Download export artifacts
- ✅ Setup SSH key
- ✅ Test SSH connection to PROD
- ✅ Create pre-deployment backup
- ✅ Transfer export package to PROD
- ✅ Run import script on PROD
- ✅ Download import logs
- ✅ Run smoke tests
- ✅ Clean up temporary files
- ✅ Upload deployment artifacts
- ✅ Create deployment report

## Troubleshooting

### If Export Fails
- Check SSH connection to DEV VPS
- Verify export script exists: `/srv/n8n/scripts/export_from_dev.sh`
- Check DEV n8n is running: `docker ps | grep n8n`

### If Import Fails
- Check SSH connection to PROD VPS
- Verify import script exists: `/srv/n8n/scripts/import_to_prod.sh`
- Check PROD n8n is running: `docker ps | grep n8n`
- Verify encryption keys are set correctly

### If Smoke Tests Fail
- Check n8n container is running
- Verify database connectivity
- Check workflow count in database

## Success Indicators

✅ **Workflow completes without errors**  
✅ **Export package created on DEV**  
✅ **Import completed on PROD**  
✅ **Smoke tests pass**  
✅ **Workflows visible in PROD n8n UI**  
✅ **Active workflows are activated**

---

**Ready to test!** Follow the steps above to manually trigger and verify the workflow.

