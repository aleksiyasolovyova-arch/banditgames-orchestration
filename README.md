# Environment Setup

This project uses an `.env` file to configure all secrets (database credentials, admin users, etc.).  
To keep your secrets safe, the repository includes a public `.env.example` file that you can copy and fill in.

---

## Create your environment file

Copy the example template:

```bash
cp .env.example .env
```
Fill in the credentials.

Make sure the `.env` stays local (DO NOT COMMIT) 

```bash
docker compose up 

```

# Test local/remote images

