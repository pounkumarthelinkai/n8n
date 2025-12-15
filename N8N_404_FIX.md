# Fixing n8n 404 Error

## Current Status

✅ **n8n is running** - Container is up and healthy  
✅ **Traefik routing works** - HTTPS returns 200  
✅ **Health check passes** - API is responding  
⚠️ **Fresh database** - User accounts need to be recreated  

---

## The Issue

When we restored DEV, we created a **fresh database**. This means:
- All workflows are restored ✅
- All credentials are restored ✅
- **User accounts were reset** ⚠️

---

## Solutions

### Solution 1: Access Setup Page (Recommended)

Since the database is fresh, you need to create the first user account:

1. **Go to:** https://n8n.thelinkai.com/setup
2. **Create your account:**
   - Enter your email
   - Set a password
   - Complete the setup

3. **After setup, you'll be able to access:**
   - https://n8n.thelinkai.com/home/workflows
   - All your workflows (93 workflows)
   - All your credentials (98 credentials)

### Solution 2: Check Browser Cache

If you still see 404:

1. **Clear browser cache:**
   - Press `Ctrl + Shift + Delete`
   - Clear cached images and files
   - Reload the page

2. **Try incognito/private mode:**
   - Open https://n8n.thelinkai.com in incognito window
   - This bypasses cache issues

### Solution 3: Check URL

Make sure you're accessing:
- ✅ **Correct:** https://n8n.thelinkai.com
- ✅ **Correct:** https://n8n.thelinkai.com/setup
- ✅ **Correct:** https://n8n.thelinkai.com/home/workflows
- ❌ **Wrong:** http://n8n.thelinkai.com (should be HTTPS)

---

## Verification Commands

```bash
# Check n8n is running
ssh -i C:\Users\admin\.ssh\github_deploy_key root@194.238.17.118
docker ps | grep n8n

# Check health
curl https://n8n.thelinkai.com/healthz
# Should return: {"status":"ok"}

# Check main page
curl -I https://n8n.thelinkai.com
# Should return: HTTP/2 200
```

---

## What Was Restored

✅ **93 workflows** - All imported  
✅ **98 credentials** - All imported  
✅ **Fresh database** - Clean, no corruption  
⚠️ **User accounts** - Need to be recreated  

---

## Next Steps

1. **Go to:** https://n8n.thelinkai.com/setup
2. **Create your account** (first user becomes owner)
3. **Access workflows:** https://n8n.thelinkai.com/home/workflows
4. **Activate workflows** as needed

---

## If Setup Page Also Shows 404

If even the setup page shows 404:

1. **Wait 2-3 minutes** - n8n might still be initializing
2. **Check logs:**
   ```bash
   ssh -i C:\Users\admin\.ssh\github_deploy_key root@194.238.17.118
   docker logs root-n8n-1 --tail 20
   ```
3. **Restart n8n:**
   ```bash
   cd /root
   docker compose restart n8n
   ```

---

**Status:** n8n is running and accessible  
**Action Required:** Create first user account at /setup page

