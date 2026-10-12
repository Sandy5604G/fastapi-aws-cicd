import os
import time

from fastapi import FastAPI

START = time.time()
VERSION = os.getenv("APP_VERSION", "dev")

app = FastAPI(title="FastAPI CI/CD on AWS ECS", version=VERSION)


@app.get("/")
def root():
    return {"message": "Hello from FastAPI on AWS ECS Fargate", "version": VERSION}


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/version")
def version():
    return {"version": VERSION, "uptime_seconds": round(time.time() - START, 1)}
