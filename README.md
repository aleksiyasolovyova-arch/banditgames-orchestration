# Environment Setup

This project uses an `.env` file for configuration (database credentials, admin users, paths, etc.).  
To keep your secrets safe, the repository includes a public `.env.example` file that you can copy and fill in.

---

## Create your environment file

Copy the example template:

```bash
cp .env.example .env
```
Fill in the credentials, paths and image names.

Make sure the `.env` stays local (DO NOT COMMIT) 

# Test local/remote images

There is one docker-compose.yml base file
It defines the main infrastructure and configuration of our services

To run services with their remote versions run:

```bash
docker compose up
```

To make one of the services uses your local version for testing run:

```bash
docker compose -f docker-compose.yml -f docker-compose.platform-backend.local.yml up --build 
```

Replace the second file with whatever file you want to use for the local version of the service, you can also add multiple -f flags to use multiple local versions of services that you want to test
